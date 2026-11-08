// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestCore

@Suite("VirtualMachineLibrary")
struct VirtualMachineLibraryTests {
    @Test("a created bundle round-trips its configuration")
    func roundTrip() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let config = VirtualMachineConfiguration.fixture()

        let bundle = try library.createBundle(for: config)

        #expect(bundle.url.lastPathComponent == "Ubuntu.nestvm")
        #expect(try library.loadConfiguration(of: bundle) == config)
        #expect(try library.entries() == [.machine(bundle, config)])
    }

    @Test("creation dates are stored in whole seconds and round-trip exactly")
    func preciseDates() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let config = VirtualMachineConfiguration(
            name: "Precise", guest: .linux, cpuCount: 2, memorySize: .gibibytes(2), diskSize: .gibibytes(16),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000.123)
        )
        let bundle = try library.createBundle(for: config)
        let loaded = try library.loadConfiguration(of: bundle)
        #expect(config.createdAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(loaded == config)
    }

    @Test("dates with fractional seconds are accepted when reading")
    func fractionalDates() throws {
        let json = Data(#""2027-01-15T10:00:00.250Z""#.utf8)
        let date = try VirtualMachineLibrary.makeDecoder().decode(Date.self, from: json)
        #expect(date == Date(timeIntervalSince1970: 1_800_007_200.25))
    }

    @Test("machine names are unique, ignoring case")
    func uniqueNames() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        try library.createBundle(for: .fixture(name: "Ubuntu"))
        #expect(library.isNameInUse("ubuntu "))
        #expect(throws: VirtualMachineLibraryError.nameInUse("UBUNTU")) {
            try library.createBundle(for: .fixture(name: "UBUNTU"))
        }
    }

    @Test("different names that sanitize to the same file name get distinct bundles")
    func sanitizedCollisions() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let first = try library.createBundle(for: .fixture(name: "a/b"))
        let second = try library.createBundle(for: .fixture(name: "a:b"))
        #expect(first.url.lastPathComponent == "a-b.nestvm")
        #expect(second.url.lastPathComponent == "a-b 2.nestvm")
    }

    @Test("file names are sanitized", arguments: [
        ("Dev/Test", "Dev-Test"),
        ("a:b", "a-b"),
        ("..hidden", "hidden"),
        ("   ", "Virtual Machine"),
    ])
    func sanitizing(input: String, expected: String) {
        #expect(VirtualMachineLibrary.sanitizedFileName(input) == expected)
    }

    @Test("entries are sorted by name using Finder ordering")
    func sorting() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        try library.createBundle(for: .fixture(name: "VM 10"))
        try library.createBundle(for: .fixture(name: "VM 2"))
        try library.createBundle(for: .fixture(name: "Alpine"))
        let names = try library.entries().compactMap { entry -> String? in
            if case let .machine(_, config) = entry {
                config.name
            } else {
                nil
            }
        }
        #expect(names == ["Alpine", "VM 2", "VM 10"])
    }

    @Test("a bundle without config.json is reported as damaged, not hidden")
    func missingConfiguration() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let url = directory.url.appending(path: "Broken.nestvm")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let bundle = VirtualMachineBundle(url: url)
        #expect(try library.entries() == [.damaged(bundle, .configurationMissing(bundle.url))])
    }

    @Test("a configuration from a newer app version is rejected with a clear error")
    func newerSchema() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        var config = VirtualMachineConfiguration.fixture()
        config.schemaVersion = 99
        let bundle = try library.createBundle(for: config)

        #expect(throws: VirtualMachineLibraryError.unsupportedSchemaVersion(found: 99, supported: 1)) {
            try library.loadConfiguration(of: bundle)
        }
    }

    @Test("garbage in config.json is reported as unreadable")
    func corruptConfiguration() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let bundle = try library.createBundle(for: .fixture())
        try Data("not json".utf8).write(to: bundle.configurationURL)

        guard case .damaged(_, .configurationUnreadable) = try #require(library.entries().first) else {
            Issue.record("expected an unreadable entry")
            return
        }
    }

    @Test("non-bundle files in the library folder are ignored")
    func ignoresOtherFiles() throws {
        let directory = try TemporaryDirectory()
        try Data().write(to: directory.url.appending(path: "notes.txt"))
        #expect(try VirtualMachineLibrary(rootURL: directory.url).entries().isEmpty)
    }
}
