// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Darwin
import Foundation
import NestCore
import NestImages
import NestSpec
import NestVirtualization

// MARK: - create

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a Linux machine.",
        discussion: """
        Example: nestctl create dev --memory 8GiB --share ~/Projects/app:workspace
        Resources default to “auto”: sensible values for this Mac.
        """
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Machine name.") var name: String
    @Option(help: "Number of CPUs, or “auto”.") var cpus = "auto"
    @Option(help: "Memory, e.g. 4GiB, or “auto”.") var memory = "auto"
    @Option(help: "Disk size, e.g. 64GiB, or “auto”.") var disk = "auto"
    @Option(
        name: .customLong("share"),
        help: ArgumentHelp("Share a Mac folder: path[:tag][:ro]. Repeatable.", valueName: "folder")
    )
    var shares: [String] = []
    @Flag(help: "Disable the shared clipboard.") var noClipboard = false
    @Flag(help: "Disable Rosetta for x86-64 binaries.") var noRosetta = false
    @Flag(help: "Create the machine without network access.") var offline = false

    func run() throws {
        let environment = Environment.current
        let renderer = Renderer(json: options.json, sink: environment.sink)
        let library = options.resolvedLibrary()
        if try library.entry(named: name) != nil {
            throw renderer.fail("a machine named “\(name)” already exists", code: NestExitCode.cannotCreate)
        }

        let host = environment.host()
        var config: VirtualMachineConfiguration
        do {
            config = try MachineSpec(
                name: name, guest: .linux,
                cpus: amount(cpus) { Int($0).flatMap { $0 > 0 ? $0 : nil } },
                memory: amount(memory) { try? ByteSize.parse($0) },
                disk: amount(disk) { try? ByteSize.parse($0) },
                rosetta: noRosetta ? false : nil,
                clipboard: !noClipboard,
                network: offline ? .disconnected : .nat
            ).configuration(host: host)
            config.sharedFolders = try shares.map(Self.sharedFolder)
        } catch let error as ValidationError {
            throw renderer.fail(error.message, code: NestExitCode.usage)
        }

        let issues = ConfigurationValidator(host: host).issues(in: config)
        if let error = issues.first(where: { $0.severity == .error }) {
            throw renderer.fail(error.englishDescription, code: NestExitCode.invalidInput)
        }
        let bundle = try library.createBundle(for: config)
        let machine = MachineDTO(entry: .machine(bundle, config))
        try renderer.emit(machine) {
            let resources = "\(config.cpuCount) CPUs, \(config.memorySize) memory, \(config.diskSize) disk"
            var lines = ["✔ created \(config.name): \(resources)"]
            lines += issues.map { "warning: \($0.englishDescription)" }
            lines.append("  Install Linux with: nestctl run \(config.name) --iso <installer.iso> --console")
            return lines.joined(separator: "\n")
        }
    }

    private func amount<Value>(_ text: String, parse: (String) -> Value?) throws -> Amount<Value> {
        if text == "auto" {
            return .auto
        }
        guard let value = parse(text) else { throw ValidationError("“\(text)” is not a valid value") }
        return .fixed(value)
    }

    /// Parses `path[:tag][:ro]` into a shared folder with a (non-security-scoped) bookmark.
    static func sharedFolder(_ text: String) throws -> SharedFolder {
        var parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let readOnly = parts.count > 1 && parts.last == "ro"
        if readOnly {
            parts.removeLast()
        }
        guard let path = parts.first, !path.isEmpty, parts.count <= 2 else {
            throw ValidationError("“\(text)” is not a share; write path[:tag][:ro]")
        }
        let url = URL(filePath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw ValidationError("“\(path)” is not an existing folder") }
        let tag = parts.count == 2 ? parts[1] : url.lastPathComponent
        return try SharedFolder(name: tag, bookmark: url.bookmarkData(), isReadOnly: readOnly)
    }
}

// MARK: - run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a machine in this terminal and keep it running until it shuts down.",
        discussion: """
        Ctrl-C asks the guest to shut down cleanly; press it twice to power off immediately.
        With --console the terminal is connected to the guest’s serial console; press Ctrl-] to shut down.
        Requires a signed nestctl (make nestctl).
        """
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Machine name.") var name: String
    @Option(
        help: "Attach an installer for this run: a path to an ISO, or a catalog installer such as debian-13-netinst.",
        completion: .file(extensions: ["iso"])
    )
    var iso: String?
    @Flag(help: "Connect the terminal to the guest’s serial console.") var console = false

    /// Not `@MainActor` itself: an isolated `run()` would not satisfy the protocol requirement and
    /// ArgumentParser would fall back to printing help. The work hops to the main actor instead.
    func run() async throws {
        try await execute()
    }

    @MainActor
    private func execute() async throws {
        let renderer = Renderer(json: options.json, sink: Environment.current.sink)
        let library = options.resolvedLibrary()
        guard let entry = try library.entry(named: name), case let .machine(bundle, config) = entry else {
            throw renderer.fail("no machine named “\(name)” (see `nestctl list`)", code: NestExitCode.notFound)
        }
        let bootMedia = try await resolveBootMedia(renderer: renderer)

        let session = VirtualMachineSession(bundle: bundle, configuration: config)
        let terminal = console ? TerminalConsole() : nil
        defer { terminal?.restore() }

        let states = session.states()
        do {
            try await session.start(bootMedia: bootMedia, console: terminal?.output ?? .logFile)
        } catch let error as EngineError {
            throw renderer.fail(error.description, code: Self.exitCode(for: error))
        }
        if !console {
            Environment.current.sink
                .write("▶ \(config.name) is running — Ctrl-C shuts it down. Console: nestctl logs \(config.name) -f")
        }

        let interrupts = Self.handleInterrupts(session: session, announce: !console)
        terminal?.onEscape = { Task { @MainActor in try? session.requestStop() } }
        defer { interrupts.cancel() }
        try await waitUntilStopped(states, name: config.name, renderer: renderer)
    }

    /// First Ctrl-C asks the guest to shut down; any further Ctrl-C powers it off.
    @MainActor
    private static func handleInterrupts(session: VirtualMachineSession, announce: Bool) -> InterruptHandler {
        let name = session.configuration.name
        return InterruptHandler { count in
            Task { @MainActor in
                if count == 1, session.state == .running {
                    if announce {
                        Environment.current.sink.write("◼ shutting down \(name)… (Ctrl-C again to power off)")
                    }
                    try? session.requestStop()
                } else {
                    try? await session.forceStop()
                }
            }
        }
    }

    /// Returns when the machine has stopped; throws when it failed.
    @MainActor
    private func waitUntilStopped(
        _ states: AsyncStream<VirtualMachineState>, name: String, renderer: Renderer
    ) async throws {
        // The stream starts with the state before `start()` (stopped); only a stop after the machine
        // was active ends the run.
        var wasActive = false
        for await state in states {
            if state.isActive {
                wasActive = true
            }
            switch state {
            case .stopped where wasActive:
                if !console {
                    Environment.current.sink.write("✔ \(name) stopped")
                }
                return
            case let .failed(failure):
                throw renderer.fail("\(name) stopped unexpectedly: \(failure)", code: NestExitCode.failure)
            default:
                continue
            }
        }
    }

    /// A local ISO path, or a catalog installer that is downloaded and verified first.
    @MainActor
    private func resolveBootMedia(renderer: Renderer) async throws -> BootMedia {
        guard let iso else { return .none }
        let path = URL(filePath: (iso as NSString).expandingTildeInPath).standardizedFileURL
        if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
            return .installer(path)
        }
        guard let image = ImageCatalog.image(named: iso) else {
            throw renderer.fail(
                "“\(iso)” is neither a file nor a catalog image (see `nestctl images`)",
                code: NestExitCode.notFound
            )
        }
        guard image.kind == .installer else {
            throw renderer.fail(
                "“\(image.id)” is a cloud image; use it as `image:` in a Nestfile",
                code: NestExitCode.invalidInput
            )
        }
        let store = ImageStore(rootURL: ImageStore.appImagesURL())
        if store.cachedImage(for: image) == nil {
            Environment.current.sink.write("↓ downloading \(image.displayName) (≈ \(image.downloadSize))")
        }
        let progress = ProgressLine(label: image.id, sink: Environment.current.sink)
        do {
            return try await .installer(store.fetch(image) { progress.update($0) })
        } catch let error as ImageError {
            throw renderer.fail(error.description, code: NestExitCode.failure)
        }
    }

    static func exitCode(for error: EngineError) -> ExitCode {
        switch error {
        case .bootMediaMissing, .sharedFolderUnavailable: NestExitCode.notFound
        case .inUseByAnotherProcess, .alreadyRunning: NestExitCode.temporaryFailure
        case .invalidConfiguration, .invalidSharedFolderTag, .guestNotYetSupported, .rosettaNotInstalled:
            NestExitCode.invalidInput
        default: NestExitCode.failure
        }
    }
}

/// SIGINT handling that counts presses, so the first Ctrl-C can shut down cleanly and the second forces.
final class InterruptHandler: @unchecked Sendable {
    // @unchecked: `count` is only touched on the main queue by the dispatch source.
    private let source: DispatchSourceSignal
    private var count = 0

    init(handler: @escaping @Sendable (Int) -> Void) {
        signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            count += 1
            handler(count)
        }
        source.resume()
    }

    func cancel() {
        source.cancel()
        signal(SIGINT, SIG_DFL)
    }
}

/// Connects the terminal to the guest’s serial console in raw mode. Ctrl-] is intercepted to shut
/// the machine down; everything else (including Ctrl-C) goes to the guest.
@MainActor
final class TerminalConsole {
    private static let escapeByte: UInt8 = 0x1D // Ctrl-]

    private var original = termios()
    private var isRaw = false
    private let toGuest = Pipe()
    private var reader: DispatchSourceRead?
    var onEscape: (() -> Void)?

    var output: ConsoleOutput {
        .handles(read: toGuest.fileHandleForReading, write: FileHandle.standardOutput)
    }

    init() {
        if tcgetattr(STDIN_FILENO, &original) == 0 {
            var raw = original
            cfmakeraw(&raw)
            raw.c_oflag |= tcflag_t(OPOST | ONLCR) // keep newline translation readable
            isRaw = tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        let writer = toGuest.fileHandleForWriting
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            guard count > 0 else { return }
            let bytes = buffer.prefix(count)
            if bytes.contains(Self.escapeByte) {
                MainActor.assumeIsolated { self?.onEscape?() }
                return
            }
            writer.write(Data(bytes))
        }
        source.resume()
        reader = source
    }

    func restore() {
        reader?.cancel()
        reader = nil
        if isRaw {
            tcsetattr(STDIN_FILENO, TCSANOW, &original)
            isRaw = false
        }
    }
}

// MARK: - logs

struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show a machine’s serial console output.")

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Machine name.") var name: String
    @Flag(name: .shortAndLong, help: "Keep printing new output.") var follow = false

    func run() async throws {
        let renderer = Renderer(json: false, sink: Environment.current.sink)
        guard let entry = try options.resolvedLibrary().entry(named: name) else {
            throw renderer.fail("no machine named “\(name)”", code: NestExitCode.notFound)
        }
        let url = entry.id.appending(path: "Console.log")
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw renderer.fail("\(name) has no console output yet (start it first)", code: NestExitCode.notFound)
        }
        defer { try? handle.close() }
        repeat {
            if let data = try handle.readToEnd(), !data.isEmpty {
                FileHandle.standardOutput.write(data)
            }
            if follow {
                try await Task.sleep(for: .milliseconds(250))
            }
        } while follow && !Task.isCancelled
    }
}
