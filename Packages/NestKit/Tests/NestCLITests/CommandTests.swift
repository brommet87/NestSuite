// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Foundation
import NestCore
import Testing
@testable import NestCLI

/// Captures command output instead of printing it.
final class CapturingOutput: OutputSink, @unchecked Sendable {
    // @unchecked: only used from the serialized test suite below.
    private(set) var out = ""
    private(set) var err = ""

    func write(_ text: String) {
        out += text + "\n"
    }

    func writeError(_ text: String) {
        err += text + "\n"
    }
}

/// End-to-end tests of `nestctl` commands against a temporary library.
/// Serialized because commands read their dependencies from `Environment.current`.
@Suite("nestctl", .serialized)
struct CommandTests {
    static let host = HostCapabilities(
        cpuCount: 8, physicalMemory: .gibibytes(16), minimumCPUCount: 1, maximumCPUCount: 8,
        minimumMemorySize: .mebibytes(128), maximumMemorySize: .gibibytes(16),
        isRosettaAvailable: true, supportsMacOSGuests: true
    )

    let root: URL
    let library: VirtualMachineLibrary
    let output = CapturingOutput()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nestctl-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = VirtualMachineLibrary(rootURL: root.appending(path: "Machines"))
        let sink = output
        let cwd = root
        Environment.current = Environment(sink: sink, host: { Self.host }, currentDirectory: { cwd })
    }

    /// Runs a command line and returns its exit code, like the shell would see it.
    @discardableResult
    func run(_ arguments: [String]) -> Int32 {
        do {
            var command = try NestCtl.parseAsRoot(arguments + [
                "--library",
                library.rootURL.path(percentEncoded: false),
            ])
            try command.run()
            return 0
        } catch {
            return NestCtl.exitCode(for: error).rawValue
        }
    }

    func json(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    @discardableResult
    func makeMachine(_ name: String, guest: GuestOperatingSystem = .linux) throws -> VirtualMachineBundle {
        try library.createBundle(for: .recommended(for: guest, name: name, host: Self.host))
    }

    // MARK: list / inspect

    @Test("list prints a table and an empty-library hint")
    func list() throws {
        run(["list"])
        #expect(output.out.contains("No virtual machines"))

        try makeMachine("Ubuntu")
        run(["list"])
        #expect(output.out.contains("NAME"))
        #expect(output.out.contains("Ubuntu"))
    }

    @Test("list --json is a stable array of machines with sizes in bytes")
    func listJSON() throws {
        try makeMachine("Ubuntu")
        #expect(run(["list", "--json"]) == 0)
        let machines = try #require(try json(output.out) as? [[String: Any]])
        #expect(machines.count == 1)
        #expect(machines[0]["name"] as? String == "Ubuntu")
        #expect(machines[0]["memoryBytes"] as? Int == 4 * 1024 * 1024 * 1024)
        #expect(machines[0]["status"] as? String == "stopped")
    }

    @Test("inspect a missing machine exits 66 and prints JSON in JSON mode")
    func inspectMissing() throws {
        #expect(run(["inspect", "ghost", "--json"]) == 66)
        let error = try #require(try json(output.out) as? [String: Any])
        #expect(error["exitCode"] as? Int == 66)
    }

    @Test("inspect finds machines case-insensitively")
    func inspect() throws {
        try makeMachine("Dev Box")
        #expect(run(["inspect", "dev box"]) == 0)
        #expect(output.out.contains("Dev Box"))
    }

    // MARK: clone / rm

    @Test("clone --count creates numbered linked clones")
    func cloneMany() throws {
        try makeMachine("base")
        #expect(run(["clone", "base", "ci", "--count", "3", "--json"]) == 0)
        let names = try library.entries().compactMap { entry -> String? in
            if case let .machine(_, config) = entry {
                config.name
            } else {
                nil
            }
        }
        #expect(names == ["base", "ci-1", "ci-2", "ci-3"])
    }

    @Test("clone refuses to overwrite existing machines", arguments: [["ci"], ["ci", "--count", "2"]])
    func cloneConflict(extra: [String]) throws {
        try makeMachine("base")
        try makeMachine(extra.count == 1 ? "ci" : "ci-2")
        #expect(run(["clone", "base"] + extra) == 73)
    }

    @Test("clone validates --count")
    func cloneCount() {
        #expect(run(["clone", "a", "b", "--count", "0"]) == 64)
    }

    @Test("rm resolves all names before removing anything")
    func removeAtomic() throws {
        try makeMachine("a")
        try makeMachine("b")
        #expect(run(["rm", "--force", "a", "typo"]) == 66)
        #expect(try library.entries().count == 2)
        #expect(run(["rm", "--force", "a", "b"]) == 0)
        #expect(try library.entries().isEmpty)
    }

    // MARK: snapshot

    @Test("snapshot create, list as tree, restore with --yes, delete")
    func snapshots() throws {
        let bundle = try makeMachine("dev")
        try Data("v1".utf8).write(to: bundle.diskImageURL)

        #expect(run(["snapshot", "create", "dev", "clean"]) == 0)
        try Data("v2".utf8).write(to: bundle.diskImageURL)
        #expect(run(["snapshot", "create", "dev", "after-tests"]) == 0)

        #expect(run(["snapshot", "list", "dev"]) == 0)
        #expect(output.out.contains("○ clean"))
        #expect(output.out.contains("└─● after-tests"))

        #expect(run(["snapshot", "restore", "dev", "clean"]) == 64, "restore needs --yes")
        #expect(run(["snapshot", "restore", "dev", "clean", "--yes"]) == 0)
        #expect(try String(contentsOf: bundle.diskImageURL, encoding: .utf8) == "v1")

        #expect(run(["snapshot", "rm", "dev", "after-tests"]) == 0)
        #expect(run(["snapshot", "rm", "dev", "after-tests"]) == 66)
        #expect(run(["snapshot", "create", "dev", "clean"]) == 73, "names are unique")
    }

    @Test("snapshot list --json marks the current snapshot")
    func snapshotJSON() throws {
        try makeMachine("dev")
        run(["snapshot", "create", "dev", "one"])
        run(["snapshot", "create", "dev", "two"])
        let before = output.out.count
        #expect(run(["snapshot", "list", "dev", "--json"]) == 0)
        let list = try #require(try json(String(output.out.dropFirst(before))) as? [[String: Any]])
        #expect(list.compactMap { $0["isHead"] as? Bool } == [false, true])
    }

    // MARK: validate

    @Test("validate finds the Nestfile in the current folder")
    func validateValid() throws {
        try Data("version: 1\nmachines:\n  dev: { guest: linux, image: ubuntu-24.04 }\n".utf8)
            .write(to: root.appending(path: "Nestfile.yml"))
        #expect(run(["validate"]) == 0)
        #expect(output.out.contains("✔ Nestfile.yml: 1 machine, valid"))
    }

    @Test("validate reports schema errors with exit code 65")
    func validateSchemaError() throws {
        try Data("version: 1\nmachines:\n  dev: { guest: linux, memroy: 8GiB }\n".utf8)
            .write(to: root.appending(path: "Nestfile.yml"))
        #expect(run(["validate", "--json"]) == 65)
        let result = try #require(try json(output.out) as? [String: Any])
        #expect(result["valid"] as? Bool == false)
    }

    @Test("--strict turns warnings into failures")
    func validateStrict() throws {
        try Data("version: 1\nmachines:\n  dev: { guest: linux }\n".utf8)
            .write(to: root.appending(path: "Nestfile.yml"))
        #expect(run(["validate"]) == 0)
        #expect(run(["validate", "--strict"]) == 65)
    }

    @Test("validate without a Nestfile exits 66")
    func validateMissing() {
        #expect(run(["validate"]) == 66)
    }

    // MARK: host / environment

    @Test("host --json exposes the limits")
    func host() throws {
        #expect(run(["host", "--json"]) == 0)
        let dto = try #require(try json(output.out) as? [String: Any])
        #expect(dto["cpuRange"] as? [Int] == [1, 8])
    }

    @Test("the library comes from --library, then NESTSUITE_LIBRARY, then the app")
    func libraryResolution() throws {
        let explicit = try GlobalOptions.parse(["--library", "/tmp/a"])
        #expect(explicit.resolvedLibrary(environment: ["NESTSUITE_LIBRARY": "/tmp/b"]).rootURL
            .path(percentEncoded: false) == "/tmp/a/")
        let fromEnv = try GlobalOptions.parse([])
        #expect(fromEnv.resolvedLibrary(environment: ["NESTSUITE_LIBRARY": "/tmp/b"]).rootURL
            .path(percentEncoded: false) == "/tmp/b/")
        #expect(fromEnv.resolvedLibrary(environment: [:]).rootURL == VirtualMachineLibrary.appLibraryURL())
    }

    @Test("tables align columns")
    func tableLayout() {
        #expect(table(header: ["A", "BB"], rows: [["long", "x"]]) == "A     BB\nlong  x")
    }
}
