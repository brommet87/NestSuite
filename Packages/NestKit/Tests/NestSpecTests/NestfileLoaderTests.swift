// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Testing
@testable import NestSpec

@Suite("NestfileLoader")
struct NestfileLoaderTests {
    let url = URL(filePath: "/projects/app/Nestfile.yml")

    private func parse(_ yaml: String) throws(NestfileError) -> Nestfile {
        try NestfileLoader.parse(yaml, url: url)
    }

    private func error(_ yaml: String) -> NestfileError? {
        do {
            _ = try parse(yaml)
            return nil
        } catch {
            return error
        }
    }

    /// A full fixture is clearer in one place than split up.
    @Test("a complete machine definition")
    // swiftlint:disable:next function_body_length
    func complete() throws {
        let nestfile = try parse("""
        version: 1
        machines:
          dev:
            guest: linux
            image: ubuntu-24.04
            cpus: 4
            memory: 8GiB
            disk: 40GiB
            rosetta: true
            clipboard: false
            network: nat
            shares:
              - host: .
                tag: workspace
              - host: ~/Datasets
                readOnly: true
            ports:
              - 3000
              - "8080:80"
              - "5353:53/udp"
              - { host: 9000, guest: 9001, protocol: tcp }
            provision:
              cloudInit: ./cloud-init.yaml
            hooks:
              preStart: scripts/pre-start.sh
        """)

        #expect(nestfile.version == 1)
        let dev = try #require(nestfile.machines.first)
        #expect(dev.name == "dev")
        #expect(dev.guest == .linux)
        #expect(dev.image == "ubuntu-24.04")
        #expect(dev.cpus == .fixed(4))
        #expect(dev.memory == .fixed(.gibibytes(8)))
        #expect(dev.disk == .fixed(.gibibytes(40)))
        #expect(dev.rosetta == true)
        #expect(dev.clipboard == false)
        #expect(dev.shares == [
            ShareSpec(hostURL: URL(filePath: "/projects/app"), tag: "workspace"),
            ShareSpec(
                hostURL: URL(filePath: NSString("~/Datasets").expandingTildeInPath),
                tag: "Datasets", readOnly: true
            ),
        ])
        #expect(dev.ports == [
            PortForward(hostPort: 3000, guestPort: 3000),
            PortForward(hostPort: 8080, guestPort: 80),
            PortForward(hostPort: 5353, guestPort: 53, transport: .udp),
            PortForward(hostPort: 9000, guestPort: 9001),
        ])
        #expect(dev.provision?.cloudInit == URL(filePath: "/projects/app/cloud-init.yaml"))
        #expect(dev.hooks.preStart == URL(filePath: "/projects/app/scripts/pre-start.sh"))
    }

    @Test("minimal machines use automatic resources")
    func defaults() throws {
        let nestfile = try parse("""
        version: 1
        machines:
          ci:
            guest: macOS
        """)
        let machine = try #require(nestfile.machines.first)
        #expect(machine.cpus == .auto)
        #expect(machine.memory == .auto)
        #expect(machine.clipboard)
        #expect(machine.network == .nat)
        #expect(machine.rosetta == nil)
    }

    @Test("machines keep file order")
    func order() throws {
        let nestfile = try parse("""
        version: 1
        machines:
          web: { guest: linux }
          db: { guest: linux }
          app: { guest: linux }
        """)
        #expect(nestfile.machines.map(\.name) == ["web", "db", "app"])
    }

    @Test("explicit auto is accepted")
    func explicitAuto() throws {
        let nestfile = try parse("version: 1\nmachines:\n  a: { guest: linux, cpus: auto, memory: auto }")
        #expect(nestfile.machines.first?.cpus == .auto)
    }

    @Test("typos in keys are errors with a suggestion and a line number")
    func unknownKey() {
        let failure = error("""
        version: 1
        machines:
          dev:
            guest: linux
            memroy: 8GiB
        """)
        #expect(failure == NestfileError(
            path: "machines.dev.memroy", line: 5, kind: .unknownKey("memroy", suggestion: "memory")
        ))
        #expect(failure?.description == "machines.dev.memroy, line 5: unknown key “memroy” — did you mean “memory”?")
    }

    @Test("unknown keys without a close match get no suggestion")
    func unknownKeyNoSuggestion() {
        let failure = error("version: 1\nmachines:\n  dev:\n    guest: linux\n    flavour: vanilla")
        #expect(failure?.kind == .unknownKey("flavour", suggestion: nil))
    }

    @Test("unsupported version")
    func version() {
        #expect(error("version: 2\nmachines:\n  a: { guest: linux }")?.kind == .unsupportedVersion(2))
    }

    @Test("missing required keys", arguments: [
        ("machines:\n  a: { guest: linux }", "version"),
        ("version: 1", "machines"),
        ("version: 1\nmachines:\n  a: { cpus: 2 }", "guest"),
    ])
    func missing(yaml: String, key: String) {
        #expect(error(yaml)?.kind == .missingKey(key))
    }

    @Test("invalid values are explained", arguments: [
        ("guest: windows", "machines.a.guest"),
        ("guest: linux\n    memory: 8GB", "machines.a.memory"),
        ("guest: linux\n    cpus: 0", "machines.a.cpus"),
        ("guest: linux\n    network: bridged", "machines.a.network"),
        ("guest: linux\n    ports: [\"99999\"]", "machines.a.ports[0]"),
        ("guest: linux\n    ports: [\"80:http\"]", "machines.a.ports[0]"),
        ("guest: linux\n    rosetta: maybe", "machines.a.rosetta"),
    ])
    func invalid(body: String, path: String) {
        let failure = error("version: 1\nmachines:\n  a:\n    \(body)")
        #expect(failure?.path == path)
    }

    @Test("machine names are restricted to safe characters")
    func machineNames() {
        #expect(error("version: 1\nmachines:\n  \"my vm\": { guest: linux }")?.path == "machines.my vm")
        #expect(error("version: 1\nmachines:\n  -dash: { guest: linux }") != nil)
    }

    @Test("broken YAML is a syntax error, not a crash")
    func syntax() {
        guard case .syntax = error("version: 1\nmachines: [unclosed")?.kind else {
            Issue.record("expected a syntax error")
            return
        }
    }

    @Test("an empty file reports the first missing key")
    func emptyFile() {
        #expect(error("")?.kind == .missingKey("version"))
    }

    @Test("locates the Nestfile by its default names")
    func locate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NestSpec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(NestfileLoader.locate(in: directory) == nil)
        try Data("version: 1".utf8).write(to: directory.appending(path: "Nestfile.yaml"))
        #expect(NestfileLoader.locate(in: directory)?.lastPathComponent == "Nestfile.yaml")
    }

    @Test("edit distance")
    func editDistance() {
        #expect(levenshtein("memroy", "memory") == 2)
        #expect(levenshtein("", "abc") == 3)
        #expect(levenshtein("same", "same") == 0)
    }
}
