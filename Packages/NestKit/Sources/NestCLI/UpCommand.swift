// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Foundation
import NestCore
import NestImages
import NestSpec
import NestVirtualization

/// `nestctl up` — create missing machines from the Nestfile and run them all, like `compose up`.
struct UpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Create and start the machines of a Nestfile; Ctrl-C shuts them all down.",
        discussion: """
        Missing machines are created from their catalog image (downloaded once, verified against the \
        distribution’s checksums) and provisioned with cloud-init: your user and SSH keys, shared \
        folders under /mnt/<tag>, Rosetta. Existing machines are started as they are.
        """
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Path to a Nestfile or a folder containing one.", completion: .file(extensions: ["yml", "yaml"]))
    var path: String?
    @Option(name: .customLong("only"), help: "Only these machines (repeatable).") var only: [String] = []
    @Option(help: "Images folder (default: the NestSuite app’s).", completion: .directory) var images: String?

    func run() async throws {
        try await execute()
    }

    @MainActor
    private func execute() async throws {
        let environment = Environment.current
        let renderer = Renderer(json: false, sink: environment.sink)
        let nestfile = try loadNestfile(renderer: renderer, cwd: environment.currentDirectory())
        let sessions = try await prepareSessions(nestfile: nestfile, renderer: renderer)
        try await startAll(sessions, nestfile: nestfile, renderer: renderer)
        environment.sink.write("All machines are running — Ctrl-C shuts them down.")

        let interrupts = Self.handleInterrupts(sessions, nestfile: nestfile)
        defer { interrupts.cancel() }
        try await supervise(sessions, nestfile: nestfile)
    }

    /// Validates the Nestfile and creates missing machines; returns one session per selected machine.
    @MainActor
    private func prepareSessions(
        nestfile: Nestfile, renderer: Renderer
    ) async throws -> [(spec: MachineSpec, session: VirtualMachineSession)] {
        let environment = Environment.current
        let machines = nestfile.machines.filter { only.isEmpty || only.contains($0.name) }
        guard !machines.isEmpty else {
            throw renderer.fail(
                "no matching machines in \(nestfile.url.lastPathComponent)",
                code: NestExitCode.notFound
            )
        }

        let host = environment.host()
        let errors = NestfileValidator(host: host).diagnostics(for: nestfile).filter { $0.severity == .error }
        if let first = errors.first {
            throw renderer.fail(
                "\(first.path): \(first.message) (see `nestctl validate`)",
                code: NestExitCode.invalidInput
            )
        }

        let library = options.resolvedLibrary()
        let store = ImageStore(rootURL: images.map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
            ?? ImageStore.appImagesURL())
        var sessions: [(spec: MachineSpec, session: VirtualMachineSession)] = []
        for spec in machines {
            let (bundle, config) = try await ensureMachine(
                spec,
                nestfile: nestfile,
                library: library,
                store: store,
                host: host
            )
            sessions.append((spec, VirtualMachineSession(bundle: bundle, configuration: config)))
        }
        return sessions
    }

    /// Starts machines in file order with their hooks; on a failure, everything already started is stopped.
    @MainActor
    private func startAll(
        _ sessions: [(spec: MachineSpec, session: VirtualMachineSession)], nestfile: Nestfile, renderer: Renderer
    ) async throws {
        for (spec, session) in sessions {
            try runHook(spec.hooks.preStart, event: "preStart", machine: spec.name, nestfile: nestfile)
            do {
                try await session.start()
            } catch let error as EngineError {
                await Self.stopAll(sessions.map(\.session))
                throw renderer.fail("\(spec.name): \(error)", code: Run.exitCode(for: error))
            }
            Environment.current.sink.write("▶ \(spec.name) started")
            try runHook(spec.hooks.postStart, event: "postStart", machine: spec.name, nestfile: nestfile)
        }
    }

    /// First Ctrl-C runs preStop hooks and asks every guest to shut down; any further Ctrl-C powers off.
    @MainActor
    private static func handleInterrupts(
        _ running: [(spec: MachineSpec, session: VirtualMachineSession)], nestfile: Nestfile
    ) -> InterruptHandler {
        let sink = Environment.current.sink
        return InterruptHandler { count in
            Task { @MainActor in
                if count == 1 {
                    sink.write("◼ shutting down… (Ctrl-C again to power off)")
                    for (spec, session) in running where session.state == .running {
                        try? runHook(spec.hooks.preStop, event: "preStop", machine: spec.name, nestfile: nestfile)
                        try? session.requestStop()
                    }
                } else {
                    for (_, session) in running where session.state.isActive {
                        try? await session.forceStop()
                    }
                }
            }
        }
    }

    // MARK: - Machines

    @MainActor
    private func ensureMachine(
        _ spec: MachineSpec, nestfile: Nestfile, library: VirtualMachineLibrary, store: ImageStore,
        host: HostCapabilities
    ) async throws -> (VirtualMachineBundle, VirtualMachineConfiguration) {
        let renderer = Renderer(json: false, sink: Environment.current.sink)
        if let entry = try library.entry(named: spec.name) {
            guard case let .machine(bundle, config) = entry else {
                throw renderer.fail("\(spec.name) exists but is damaged", code: NestExitCode.invalidInput)
            }
            return (bundle, config)
        }
        let image = try Self.cloudImage(for: spec, renderer: renderer)
        var config = spec.configuration(host: host)
        config.sharedFolders = try spec.shares.map {
            try SharedFolder(name: $0.tag, bookmark: $0.hostURL.bookmarkData(), isReadOnly: $0.readOnly)
        }
        let seed = try Self.seed(for: spec, configuration: config)

        let sink = Environment.current.sink
        if store.cachedImage(for: image) == nil {
            sink.write("↓ downloading \(image.displayName) (≈ \(image.downloadSize))")
        }
        let progressLine = ProgressLine(label: image.id, sink: sink)
        let bundle: VirtualMachineBundle
        do {
            bundle = try await MachineProvisioner(library: library, store: store)
                .provision(config, from: image, seed: seed) { progressLine.update($0) }
        } catch let error as ImageError {
            throw renderer.fail("\(spec.name): \(error)", code: NestExitCode.failure)
        }
        sink
            .write(
                "✔ created \(spec.name) from \(image.id) — user “\(seed.userName)”, \(seed.sshKeys.count) SSH key(s)"
            )
        return try (bundle, library.loadConfiguration(of: bundle))
    }

    /// The catalog cloud image named by the machine’s `image:`; installers and unknown names are rejected.
    private static func cloudImage(for spec: MachineSpec, renderer: Renderer) throws -> CatalogImage {
        guard let imageName = spec.image else {
            throw renderer.fail(
                "\(spec.name): set `image:` (e.g. ubuntu-24.04 or debian-13)",
                code: NestExitCode.invalidInput
            )
        }
        guard let image = ImageCatalog.image(named: imageName) else {
            throw renderer.fail("\(spec.name): \(ImageError.unknownImage(imageName))", code: NestExitCode.invalidInput)
        }
        guard image.kind == .cloud else {
            throw renderer.fail(
                "\(spec.name): “\(image.id)” is an installer; use a cloud image (see `nestctl images`)",
                code: NestExitCode.invalidInput
            )
        }
        return image
    }

    /// cloud-init setup: the Mac user with their SSH keys, shared folders, Rosetta and project config.
    private static func seed(for spec: MachineSpec, configuration config: VirtualMachineConfiguration) throws
        -> CloudInitSeed
    {
        try CloudInitSeed(
            instanceID: config.id.uuidString,
            hostname: spec.name,
            userName: NSUserName(),
            sshKeys: CloudInitSeed.localSSHKeys(),
            shares: spec.shares.map { CloudInitSeed.Share(tag: $0.tag) },
            rosetta: config.isRosettaEnabled,
            additionalUserData: spec.provision?.cloudInit.map { try String(contentsOf: $0, encoding: .utf8) }
        )
    }

    /// Reports readiness from the console log, runs postProvision once, and returns when all stopped.
    @MainActor
    private func supervise(
        _ sessions: [(spec: MachineSpec, session: VirtualMachineSession)], nestfile: Nestfile
    ) async throws {
        let sink = Environment.current.sink
        var reported = Set<String>()
        while sessions.contains(where: \.session.state.isActive) {
            for (spec, session) in sessions where !reported.contains(spec.name) {
                let log = session.bundle.url.appending(path: "Console.log")
                guard let report = MachineProvisioner.readyReport(in: log) else { continue }
                reported.insert(spec.name)
                sink.write("✔ \(spec.name) is ready\(report.isEmpty ? "" : " — \(report)")")
                let marker = session.bundle.provisionedMarkerURL
                if !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
                    FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: nil)
                    try runHook(
                        spec.hooks.postProvision,
                        event: "postProvision",
                        machine: spec.name,
                        nestfile: nestfile
                    )
                }
            }
            try await Task.sleep(for: .seconds(1))
        }
        let failed = sessions.filter {
            if case .failed = $0.session.state {
                true
            } else {
                false
            }
        }
        if let first = failed.first {
            throw Renderer(json: false, sink: sink)
                .fail("\(first.spec.name) stopped unexpectedly", code: NestExitCode.failure)
        }
        sink.write("✔ all machines stopped")
    }

    @MainActor
    static func stopAll(_ sessions: [VirtualMachineSession]) async {
        for session in sessions where session.state.isActive {
            try? await session.forceStop()
        }
    }

    // MARK: - Helpers

    private func loadNestfile(renderer: Renderer, cwd: URL) throws -> Nestfile {
        let candidate = path
            .map { URL(filePath: ($0 as NSString).expandingTildeInPath, relativeTo: cwd).standardizedFileURL }
        var isDirectory: ObjCBool = false
        let fileURL: URL? = if let candidate,
                               FileManager.default.fileExists(
                                   atPath: candidate.path(percentEncoded: false),
                                   isDirectory: &isDirectory
                               )
        {
            isDirectory.boolValue ? NestfileLoader.locate(in: candidate) : candidate
        } else if candidate == nil {
            NestfileLoader.locate(in: cwd)
        } else {
            nil
        }
        guard let fileURL else { throw renderer.fail("no Nestfile found", code: NestExitCode.notFound) }
        do {
            return try NestfileLoader.load(contentsOf: fileURL)
        } catch let error as NestfileError {
            throw renderer.fail("\(fileURL.lastPathComponent): \(error)", code: NestExitCode.invalidInput)
        }
    }
}

/// Runs a hook script with the machine name in the environment, in the Nestfile’s folder.
func runHook(_ script: URL?, event: String, machine: String, nestfile: Nestfile) throws {
    guard let script else { return }
    let process = Process()
    process.executableURL = script
    process.currentDirectoryURL = nestfile.directoryURL
    process.environment = ProcessInfo.processInfo.environment.merging(
        ["NESTSUITE_MACHINE": machine, "NESTSUITE_EVENT": event]
    ) { _, new in new }
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw Renderer(json: false, sink: Environment.current.sink).fail(
            "\(event) hook for \(machine) failed with exit code \(process.terminationStatus)",
            code: NestExitCode.failure
        )
    }
}

/// A single updating progress line on interactive terminals, sparse lines otherwise.
final class ProgressLine: @unchecked Sendable {
    // @unchecked: `lastPercent` is guarded by `lock`.
    private let label: String
    private let sink: any OutputSink
    private let lock = NSLock()
    private var lastPercent = -1
    private let interactive = isatty(STDOUT_FILENO) == 1

    init(label: String, sink: any OutputSink) {
        self.label = label
        self.sink = sink
    }

    func update(_ progress: DownloadProgress) {
        guard let fraction = progress.fractionCompleted else { return }
        let percent = Int(fraction * 100)
        lock.lock()
        defer { lock.unlock() }
        let step = interactive ? 1 : 10
        guard percent >= lastPercent + step || (percent == 100 && lastPercent != 100) else { return }
        lastPercent = percent
        let received = ByteCount(bytes: UInt64(max(progress.receivedBytes, 0)))
        if interactive {
            FileHandle.standardOutput.write(Data("\r  \(label) \(percent)% (\(received))\u{1B}[K".utf8))
            if percent == 100 {
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } else {
            sink.write("  \(label) \(percent)%")
        }
    }
}
