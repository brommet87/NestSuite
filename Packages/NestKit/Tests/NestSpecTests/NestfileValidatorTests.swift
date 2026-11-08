// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Testing
@testable import NestSpec

@Suite("NestfileValidator")
struct NestfileValidatorTests {
    static let host = HostCapabilities(
        cpuCount: 12, physicalMemory: .gibibytes(32), minimumCPUCount: 1, maximumCPUCount: 12,
        minimumMemorySize: .mebibytes(128), maximumMemorySize: .gibibytes(32),
        isRosettaAvailable: true, supportsMacOSGuests: true
    )

    let validator = NestfileValidator(host: Self.host)

    private func withProject<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NestSpec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    private func diagnostics(_ yaml: String, in directory: URL) throws -> [NestfileDiagnostic] {
        let nestfile = try NestfileLoader.parse(yaml, url: directory.appending(path: "Nestfile.yml"))
        return validator.diagnostics(for: nestfile)
    }

    @Test("a valid file has no diagnostics")
    func valid() throws {
        try withProject { directory in
            let result = try diagnostics("""
            version: 1
            machines:
              dev: { guest: linux, image: ubuntu-24.04, shares: [{ host: . }], ports: [3000] }
            """, in: directory)
            #expect(result.isEmpty)
        }
    }

    @Test("resource limits come from the shared configuration validator")
    func resources() throws {
        try withProject { directory in
            let result = try diagnostics(
                "version: 1\nmachines:\n  big: { guest: linux, image: x, cpus: 64, memory: 30GiB }",
                in: directory
            )
            #expect(result.map(\.path) == ["machines.big.cpus", "machines.big.memory"])
            #expect(result.map(\.severity) == [.error, .warning])
        }
    }

    @Test("shares must exist, be folders and have unique tags")
    func shares() throws {
        try withProject { directory in
            try Data().write(to: directory.appending(path: "file.txt"))
            let result = try diagnostics("""
            version: 1
            machines:
              dev:
                guest: linux
                image: x
                shares:
                  - { host: ./missing }
                  - { host: ./file.txt, tag: data }
                  - { host: ., tag: DATA }
            """, in: directory)
            #expect(result.map(\.path) == [
                "machines.dev.shares[0].host", "machines.dev.shares[1].host", "machines.dev.shares[2].tag",
            ])
        }
    }

    @Test("a host port can only be forwarded once across all machines")
    func portCollisions() throws {
        try withProject { directory in
            let result = try diagnostics("""
            version: 1
            machines:
              web: { guest: linux, image: x, ports: [8080, "53:53/udp"] }
              api: { guest: linux, image: x, ports: ["8080:80", "53:53"] }
            """, in: directory)
            let errors = result.filter { $0.severity == .error }
            #expect(errors.count == 1)
            #expect(errors.first?.message == "host port 8080/tcp is already forwarded by machine “web”")
            #expect(result.contains { $0.severity == .warning && $0.message.contains("privileged") })
        }
    }

    @Test("hooks must exist and be executable")
    func hooks() throws {
        try withProject { directory in
            let script = directory.appending(path: "pre.sh")
            try Data("#!/bin/sh\n".utf8).write(to: script)
            let result = try diagnostics("""
            version: 1
            machines:
              dev: { guest: linux, image: x, hooks: { preStart: pre.sh, preStop: gone.sh } }
            """, in: directory)
            #expect(result.map(\.message) == [
                "script “\(script.path(percentEncoded: false))” is not executable (chmod +x)",
                "script “\(directory.appending(path: "gone.sh").path(percentEncoded: false))” does not exist",
            ])

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: script.path(percentEncoded: false)
            )
            let fixed = try diagnostics(
                "version: 1\nmachines:\n  dev: { guest: linux, image: x, hooks: { preStart: pre.sh } }",
                in: directory
            )
            #expect(fixed.isEmpty)
        }
    }

    @Test("Linux machines without an image get a hint")
    func missingImage() throws {
        try withProject { directory in
            let result = try diagnostics("version: 1\nmachines:\n  dev: { guest: linux }", in: directory)
            #expect(result.map(\.severity) == [.warning])
            #expect(result.first?.path == "machines.dev.image")
        }
    }

    @Test("auto resources resolve to the host recommendation")
    func autoResolution() {
        let spec = MachineSpec(name: "dev", guest: .linux, memory: .fixed(.gibibytes(4)))
        let config = spec.configuration(host: Self.host)
        #expect(config.cpuCount == 6)
        #expect(config.memorySize == .gibibytes(4))
        #expect(config.isRosettaEnabled)
    }
}
