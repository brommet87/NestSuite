// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Observation
import Virtualization

/// One running (or startable) virtual machine.
///
/// Main-actor isolated: `Virtualization.framework` requires all calls on the machine’s queue, and the
/// display view needs the main thread anyway (ADR 0007). The guest itself runs on the framework’s own
/// threads, so this does not load the main thread.
///
/// All state changes go through ``VirtualMachineState/applying(_:)``; impossible transitions are
/// rejected instead of corrupting the state.
@MainActor
@Observable
public final class VirtualMachineSession {
    public let bundle: VirtualMachineBundle
    public private(set) var configuration: VirtualMachineConfiguration
    public private(set) var state: VirtualMachineState = .stopped
    /// The framework machine while active; the app attaches it to a `VZVirtualMachineView`.
    public private(set) var machine: VZVirtualMachine?

    @ObservationIgnored private var built: BuiltConfiguration?
    @ObservationIgnored private var lock: BundleLock?
    @ObservationIgnored private var delegate: SessionDelegate?
    @ObservationIgnored private var continuations: [UUID: AsyncStream<VirtualMachineState>.Continuation] = [:]

    public init(bundle: VirtualMachineBundle, configuration: VirtualMachineConfiguration) {
        self.bundle = bundle
        self.configuration = configuration
        if bundle.hasSavedState() {
            state = .suspended
        }
    }

    /// State changes as an async sequence, starting with the current state (for `nestctl`).
    public func states() -> AsyncStream<VirtualMachineState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(state)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// Boots the machine.
    public func start(bootMedia: BootMedia = .none, console: ConsoleOutput = .logFile) async throws {
        guard !state.isActive else { throw EngineError.alreadyRunning }
        let lock: BundleLock
        do {
            lock = try BundleLock(bundle: bundle)
        } catch {
            throw EngineError.inUseByAnotherProcess
        }
        guard apply(.start) else {
            lock.release()
            throw EngineError.invalidConfiguration(reason: "cannot start from \(state)")
        }
        self.lock = lock

        do {
            var builder = ConfigurationBuilder(configuration: configuration, bundle: bundle)
            builder.bootMedia = bootMedia
            builder.console = console
            let built = try builder.build()
            do {
                try built.configuration.validate()
            } catch {
                built.release()
                throw EngineError.invalidConfiguration(reason: error.localizedDescription)
            }
            // Only create the machine after validate(): an invalid configuration raises an
            // Objective-C exception in the initializer.
            let machine = VZVirtualMachine(configuration: built.configuration)
            let delegate = SessionDelegate(session: self)
            machine.delegate = delegate
            self.built = built
            self.delegate = delegate
            self.machine = machine

            try await machine.start()
            apply(.didStart)
        } catch {
            cleanUp()
            let reason = (error as? EngineError)?.description ?? error.localizedDescription
            apply(.didFail(.engineError(description: reason)))
            throw error as? EngineError ?? EngineError.startFailed(reason: reason)
        }
    }

    /// Asks the guest to shut down cleanly (ACPI power button). Returns immediately; the state becomes
    /// `.stopped` when the guest has powered off.
    public func requestStop() throws {
        guard let machine, state == .running else { throw EngineError.notRunning }
        try machine.requestStop()
    }

    /// Powers the machine off immediately, like pulling the plug. Unsaved guest data may be lost.
    public func forceStop() async throws {
        guard let machine, state.isActive else { throw EngineError.notRunning }
        apply(.stop)
        try await machine.stop()
        apply(.didStop)
        cleanUp()
    }

    public func pause() async throws {
        guard let machine, apply(.pause) else { throw EngineError.notRunning }
        try await machine.pause()
        apply(.didPause)
    }

    public func resume() async throws {
        guard let machine, apply(.resume) else { throw EngineError.notRunning }
        try await machine.resume()
        apply(.didResume)
    }

    // MARK: - Delegate callbacks

    fileprivate func guestDidStop() {
        if state == .running || state == .paused {
            apply(.stop)
        }
        apply(.didStop)
        cleanUp()
    }

    fileprivate func didStop(with error: any Error) {
        apply(.didFail(.engineError(description: error.localizedDescription)))
        cleanUp()
    }

    // MARK: - Private

    @discardableResult
    private func apply(_ event: VirtualMachineEvent) -> Bool {
        guard let next = state.applying(event) else { return false }
        state = next
        continuations.values.forEach { $0.yield(next) }
        return true
    }

    private func cleanUp() {
        built?.release()
        built = nil
        lock?.release()
        lock = nil
        machine?.delegate = nil
        machine = nil
        delegate = nil
    }
}

/// Bridges the framework’s delegate to the session. The machine runs on the main queue, so the
/// callbacks arrive on the main actor; `@preconcurrency` makes the runtime verify that.
@MainActor
private final class SessionDelegate: NSObject, @preconcurrency VZVirtualMachineDelegate {
    private weak var session: VirtualMachineSession?

    init(session: VirtualMachineSession) {
        self.session = session
    }

    func guestDidStop(_: VZVirtualMachine) {
        session?.guestDidStop()
    }

    func virtualMachine(_: VZVirtualMachine, didStopWithError error: any Error) {
        session?.didStop(with: error)
    }
}
