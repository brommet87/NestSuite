// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Foundation
import NestCore
import NestSpec
import NestVirtualization

/// `nestctl` — the NestSuite command-line interface. Reference: `docs/cli.md`.
public struct NestCtl: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "nestctl",
        abstract: "Manage NestSuite virtual machines from the command line.",
        discussion: """
        Every command supports --json for scripting. Exit codes: 0 success, 1 unexpected error, \
        64 usage error, 65 invalid input, 66 not found, 73 cannot create, 75 machine busy.
        """,
        version: "0.1.0",
        subcommands: [
            List.self, Inspect.self, Create.self, Run.self, UpCommand.self, Logs.self, Images.self, Validate.self,
            Clone.self,
            SnapshotCommand.self,
            Remove.self, Host.self,
        ]
    )

    public init() {}
}

/// Options shared by all commands.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print machine-readable JSON.")
    var json = false

    @Option(
        name: .long,
        help: ArgumentHelp("Library folder (default: the NestSuite app library).", valueName: "path"),
        completion: .directory
    )
    var library: String?

    /// `--library`, then `$NESTSUITE_LIBRARY`, then the app’s library.
    func resolvedLibrary(environment: [String: String] = ProcessInfo.processInfo.environment) -> VirtualMachineLibrary {
        let path = library ?? environment["NESTSUITE_LIBRARY"]
        let url = path.map { URL(filePath: ($0 as NSString).expandingTildeInPath, directoryHint: .isDirectory) }
        return VirtualMachineLibrary(rootURL: url ?? VirtualMachineLibrary.appLibraryURL())
    }
}

/// Dependencies a command needs; replaced in tests.
struct Environment: Sendable {
    var sink: any OutputSink = StandardOutput()
    var host: @Sendable () -> HostCapabilities = { .current() }
    var currentDirectory: @Sendable () -> URL = { URL(filePath: FileManager.default.currentDirectoryPath) }

    /// ArgumentParser instantiates commands itself, so dependencies are injected through this value.
    /// It is only replaced by tests (in a serialized suite) before a command runs.
    nonisolated(unsafe) static var current = Environment()
}

// MARK: - list

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List virtual machines.",
        aliases: ["ls"]
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let renderer = Renderer(json: options.json, sink: Environment.current.sink)
        let entries: [LibraryEntry]
        do {
            entries = try options.resolvedLibrary().entries()
        } catch {
            throw renderer.fail("cannot read the library: \(error.localizedDescription)", code: NestExitCode.failure)
        }
        let machines = entries.map(MachineDTO.init(entry:))
        try renderer.emit(machines) {
            guard !machines.isEmpty else { return "No virtual machines. Create one in NestSuite or with a Nestfile." }
            return table(
                header: ["NAME", "GUEST", "CPUS", "MEMORY", "DISK", "STATUS"],
                rows: machines.map { machine in
                    [
                        machine.name, machine.guest ?? "–", machine.cpus.map(String.init) ?? "–",
                        machine.memoryBytes.map { ByteCount(bytes: $0).description } ?? "–",
                        machine.diskBytes.map { ByteCount(bytes: $0).description } ?? "–",
                        machine.problem.map { "damaged: \($0)" } ?? machine.status,
                    ]
                }
            )
        }
    }
}

// MARK: - inspect

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show details of a virtual machine.")

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Machine name.") var name: String

    func run() throws {
        let renderer = Renderer(json: options.json, sink: Environment.current.sink)
        guard let entry = try options.resolvedLibrary().entry(named: name) else {
            throw renderer.fail("no machine named “\(name)” (see `nestctl list`)", code: NestExitCode.notFound)
        }
        let machine = MachineDTO(entry: entry)
        try renderer.emit(machine) {
            var lines = [("Name", machine.name), ("Status", machine.status)]
            if let problem = machine.problem {
                lines.append(("Problem", problem))
            }
            if let guest = machine.guest {
                lines.append(("Guest", guest))
            }
            if let cpus = machine.cpus {
                lines.append(("CPUs", String(cpus)))
            }
            if let memory = machine.memoryBytes {
                lines.append(("Memory", ByteCount(bytes: memory).description))
            }
            if let disk = machine.diskBytes {
                lines.append(("Disk", ByteCount(bytes: disk).description))
            }
            if let network = machine.network {
                lines.append(("Network", network))
            }
            if let rosetta = machine.rosetta {
                lines.append(("Rosetta", rosetta ? "on" : "off"))
            }
            if let clipboard = machine.clipboard {
                lines.append(("Clipboard", clipboard ? "shared" : "off"))
            }
            lines.append(("Path", machine.path))
            let width = lines.map(\.0.count).max() ?? 0
            return lines.map { "\($0.0.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.1)" }
                .joined(separator: "\n")
        }
    }
}

// MARK: - validate

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check a Nestfile against this Mac.",
        discussion: "Looks for Nestfile.yml, Nestfile.yaml or Nestfile in the current folder when no path is given."
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Path to a Nestfile or a folder containing one.", completion: .file(extensions: ["yml", "yaml"]))
    var path: String?

    @Flag(help: "Treat warnings as errors (useful in CI).") var strict = false

    func run() throws {
        let environment = Environment.current
        let renderer = Renderer(json: options.json, sink: environment.sink)
        guard let fileURL = resolveFile(cwd: environment.currentDirectory()) else {
            let location = path.map { " at “\($0)”" } ?? " in the current folder"
            throw renderer.fail("no Nestfile found\(location)", code: NestExitCode.notFound)
        }
        let nestfile = try load(fileURL, renderer: renderer)
        let host = environment.host()
        let diagnostics = NestfileValidator(host: host).diagnostics(for: nestfile)
        let failing = diagnostics.filter { $0.severity == .error || strict }
        let dto = ValidationDTO(
            file: fileURL.path(percentEncoded: false),
            valid: failing.isEmpty,
            machines: nestfile.machines.map { Self.machineDTO($0, host: host) },
            diagnostics: diagnostics.map {
                .init(severity: $0.severity.rawValue, path: $0.path, line: $0.line, message: $0.message)
            }
        )
        try renderer
            .emit(dto) { Self.humanReport(diagnostics, file: fileURL, nestfile: nestfile, failing: failing.count) }
        if !failing.isEmpty {
            throw NestExitCode.invalidInput
        }
    }

    /// Loads and parses the file; schema errors are reported (as JSON when requested) with exit code 65.
    private func load(_ fileURL: URL, renderer: Renderer) throws -> Nestfile {
        do {
            return try NestfileLoader.load(contentsOf: fileURL)
        } catch let error as NestfileError {
            if options.json {
                let diagnostic = ValidationDTO.Diagnostic(
                    severity: "error", path: error.path, line: error.line, message: error.message
                )
                let dto = ValidationDTO(
                    file: fileURL.path(percentEncoded: false), valid: false, machines: [], diagnostics: [diagnostic]
                )
                try renderer.emit(dto) { "" }
            } else {
                renderer.sink.writeError("\(fileURL.lastPathComponent): \(error)")
            }
            throw NestExitCode.invalidInput
        } catch {
            let message = "cannot read \(fileURL.lastPathComponent): \(error.localizedDescription)"
            throw renderer.fail(message, code: NestExitCode.notFound)
        }
    }

    private static func machineDTO(_ spec: MachineSpec, host: HostCapabilities) -> ValidationDTO.Machine {
        let config = spec.configuration(host: host)
        return ValidationDTO.Machine(
            name: spec.name, guest: spec.guest.rawValue, cpus: config.cpuCount,
            memoryBytes: config.memorySize.bytes, diskBytes: config.diskSize.bytes,
            ports: spec.ports.map(\.shortDescription),
            shares: spec.shares.map { share in
                let mode = share.readOnly ? " (read-only)" : ""
                return "\(share.hostURL.path(percentEncoded: false)) → \(share.tag)\(mode)"
            }
        )
    }

    private static func humanReport(
        _ diagnostics: [NestfileDiagnostic], file: URL, nestfile: Nestfile, failing: Int
    ) -> String {
        var lines = diagnostics.map { diagnostic in
            let location = diagnostic.line.map { "\(diagnostic.path) (line \($0))" } ?? diagnostic.path
            return "\(diagnostic.severity.rawValue): \(location): \(diagnostic.message)"
        }
        let count = nestfile.machines.count
        let summary = "\(file.lastPathComponent): \(count) machine\(count == 1 ? "" : "s")"
        lines
            .append(failing == 0 ? "✔ \(summary), valid" : "✘ \(summary), \(failing) problem\(failing == 1 ? "" : "s")")
        return lines.joined(separator: "\n")
    }

    private func resolveFile(cwd: URL) -> URL? {
        guard let path else { return NestfileLoader.locate(in: cwd) }
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(filePath: expanded) : cwd.appending(path: expanded)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        else { return nil }
        return isDirectory.boolValue ? NestfileLoader.locate(in: url) : url
    }
}

// MARK: - clone

struct Clone: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create linked clones of a machine (instant, copy-on-write on APFS).",
        discussion: "Example: nestctl clone ubuntu-base ci --count 20   → ci-1 … ci-20"
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Source machine name.") var source: String
    @Argument(help: "Name of the clone (with --count: the name prefix).") var name: String
    @Option(help: "Number of clones to create.") var count = 1

    func validate() throws {
        guard (1 ... 100).contains(count) else { throw ValidationError("--count must be between 1 and 100.") }
    }

    func run() throws {
        let renderer = Renderer(json: options.json, sink: Environment.current.sink)
        let library = options.resolvedLibrary()
        guard let entry = try library.entry(named: source) else {
            throw renderer.fail("no machine named “\(source)” (see `nestctl list`)", code: NestExitCode.notFound)
        }
        guard case .machine = entry else {
            throw renderer.fail("“\(source)” is damaged and cannot be cloned", code: NestExitCode.invalidInput)
        }
        try renderer.ensureNotRunning(entry.id, name: source)
        let names = count == 1 ? [name] : (1 ... count).map { "\(name)-\($0)" }
        if let existing = try names.first(where: { try library.entry(named: $0) != nil }) {
            throw renderer.fail("a machine named “\(existing)” already exists", code: NestExitCode.cannotCreate)
        }

        var created: [MachineDTO] = []
        for cloneName in names {
            do {
                let (bundle, configuration) = try library.clone(VirtualMachineBundle(url: entry.id), as: cloneName)
                created.append(MachineDTO(entry: .machine(bundle, configuration)))
            } catch {
                throw renderer.fail(
                    "cloning “\(cloneName)” failed: \(error.localizedDescription)",
                    code: NestExitCode.cannotCreate
                )
            }
        }
        try renderer.emit(created) {
            created.map { "✔ cloned \(source) → \($0.name)" }.joined(separator: "\n")
        }
    }
}

// MARK: - rm

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove machines (moves them to the Trash unless --force is given)."
    )

    @OptionGroup var options: GlobalOptions
    @Argument(help: "Machine names.") var names: [String]
    @Flag(name: .shortAndLong, help: "Delete permanently instead of moving to the Trash.") var force = false

    func validate() throws {
        guard !names.isEmpty else { throw ValidationError("Name at least one machine.") }
    }

    func run() throws {
        let renderer = Renderer(json: options.json, sink: Environment.current.sink)
        let library = options.resolvedLibrary()
        // Resolve everything first, so a typo in the third name doesn't leave the first two deleted.
        var targets: [LibraryEntry] = []
        for name in names {
            guard let entry = try library.entry(named: name) else {
                throw renderer.fail("no machine named “\(name)”; nothing was removed", code: NestExitCode.notFound)
            }
            try renderer.ensureNotRunning(entry.id, name: name)
            // Two names can point to the same machine (name and file name); remove it once.
            if !targets.contains(where: { $0.id == entry.id }) {
                targets.append(entry)
            }
        }
        var removed: [String] = []
        for entry in targets {
            let bundle = VirtualMachineBundle(url: entry.id)
            do {
                if force {
                    try library.removePermanently(bundle)
                } else {
                    try library.moveToTrash(bundle)
                }
                removed.append(MachineDTO(entry: entry).name)
            } catch {
                throw renderer.fail(
                    "removing “\(MachineDTO(entry: entry).name)” failed: \(error.localizedDescription)",
                    code: NestExitCode.failure
                )
            }
        }
        try renderer.emit(["removed": removed, "mode": [force ? "deleted" : "trashed"]]) {
            removed.map { "✔ \(force ? "deleted" : "moved to Trash"): \($0)" }.joined(separator: "\n")
        }
    }
}

// MARK: - host

struct Host: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what this Mac can offer to virtual machines.")

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let host = Environment.current.host()
        let dto = HostDTO(host)
        try Renderer(json: options.json, sink: Environment.current.sink).emit(dto) {
            """
            CPUs                 \(host.cpuCount) (VMs: \(host.minimumCPUCount)–\(host.maximumCPUCount))
            Memory               \(host.physicalMemory) (recommended per VM: up to \(host.recommendedMaximumMemory))
            Rosetta for Linux    \(host.isRosettaAvailable ? "available" : "not installed")
            macOS guests         \(host.supportsMacOSGuests ? "supported" : "not supported")
            """
        }
    }
}
