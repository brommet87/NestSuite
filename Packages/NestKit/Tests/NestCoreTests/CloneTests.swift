// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestCore

@Suite("Linked clones")
struct CloneTests {
    @Test("a clone is an independent machine with a new identity")
    func newIdentity() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let source = try library.createBundle(for: .fixture())
        let sourceConfig = try library.loadConfiguration(of: source)

        let (clone, cloneConfig) = try library.clone(source, as: "Ubuntu CI 1")

        #expect(clone.url.lastPathComponent == "Ubuntu CI 1.nestvm")
        #expect(cloneConfig.name == "Ubuntu CI 1")
        #expect(cloneConfig.id != sourceConfig.id)
        #expect(cloneConfig.cpuCount == sourceConfig.cpuCount)
        #expect(cloneConfig.memorySize == sourceConfig.memorySize)
        #expect(try library.loadConfiguration(of: clone) == cloneConfig)
        #expect(try library.entries().count == 2)
    }

    @Test("disk contents are copied, identity and saved state are not")
    func derivedFiles() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let source = try library.createBundle(for: .fixture())
        try Data(repeating: 0xAB, count: 4096).write(to: source.diskImageURL)
        try Data("id".utf8).write(to: source.machineIdentifierURL)
        try Data("state".utf8).write(to: source.savedStateURL)

        let (clone, _) = try library.clone(source, as: "Clone")

        #expect(try Data(contentsOf: clone.diskImageURL) == Data(repeating: 0xAB, count: 4096))
        #expect(!FileManager.default.fileExists(atPath: clone.machineIdentifierURL.path(percentEncoded: false)))
        #expect(!clone.hasSavedState())
        #expect(source.hasSavedState(), "the source must stay untouched")
    }

    @Test("writing to the clone does not change the source")
    func copyOnWrite() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let source = try library.createBundle(for: .fixture())
        try Data("original".utf8).write(to: source.diskImageURL)

        let (clone, _) = try library.clone(source, as: "Clone")
        try Data("changed".utf8).write(to: clone.diskImageURL)

        #expect(try Data(contentsOf: source.diskImageURL) == Data("original".utf8))
    }

    @Test("cloning a damaged bundle fails and leaves nothing behind")
    func damagedSource() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let broken = VirtualMachineBundle(url: directory.url.appending(path: "Broken.nestvm"))
        try FileManager.default.createDirectory(at: broken.url, withIntermediateDirectories: true)

        #expect(throws: VirtualMachineLibraryError.self) { try library.clone(broken, as: "Clone") }
        #expect(try library.entries().count == 1)
    }

    @Test("a clone cannot take an existing machine’s name")
    func cloneNameInUse() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let source = try library.createBundle(for: .fixture(name: "base"))
        try library.createBundle(for: .fixture(name: "taken"))
        #expect(throws: VirtualMachineLibraryError.nameInUse("Taken")) { try library.clone(source, as: "Taken") }
    }

    @Test("machines are found by name, case-insensitively, or by file name")
    func lookup() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let bundle = try library.createBundle(for: .fixture(name: "Dev Box"))

        #expect(try library.entry(named: "dev box")?.id == bundle.url)
        #expect(try library.entry(named: "nope") == nil)
    }

    @Test("permanent removal deletes the bundle")
    func removal() throws {
        let directory = try TemporaryDirectory()
        let library = VirtualMachineLibrary(rootURL: directory.url)
        let bundle = try library.createBundle(for: .fixture())
        try library.removePermanently(bundle)
        #expect(try library.entries().isEmpty)
    }
}
