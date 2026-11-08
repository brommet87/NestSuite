// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestCore

@Suite("Snapshots")
struct SnapshotStoreTests {
    /// The temporary directory lives as long as the suite instance (one per test), so the folder
    /// can't disappear mid-test.
    let directory: TemporaryDirectory
    let library: VirtualMachineLibrary
    let store: SnapshotStore

    init() throws {
        directory = try TemporaryDirectory()
        library = VirtualMachineLibrary(rootURL: directory.url)
        let bundle = try library.createBundle(for: .fixture())
        try Data("v1".utf8).write(to: bundle.diskImageURL)
        store = SnapshotStore(bundle: bundle)
    }

    private func disk() throws -> String {
        try String(contentsOf: store.bundle.diskImageURL, encoding: .utf8)
    }

    @Test("take, change, restore")
    func roundTrip() throws {
        let clean = try store.create(name: "clean install")
        try Data("v2 — broken by a test run".utf8).write(to: store.bundle.diskImageURL)

        try store.restore(clean)

        #expect(try disk() == "v1")
        #expect(store.head() == clean.id)
    }

    @Test("snapshots form a tree: restoring and snapshotting again creates a branch")
    func branching() throws {
        let base = try store.create(name: "base")
        try Data("feature-a".utf8).write(to: store.bundle.diskImageURL)
        let featureA = try store.create(name: "feature-a")

        try store.restore(base)
        try Data("feature-b".utf8).write(to: store.bundle.diskImageURL)
        let featureB = try store.create(name: "feature-b")

        #expect(featureA.parentID == base.id)
        #expect(featureB.parentID == base.id, "a branch off base, not off feature-a")
        #expect(try Set(store.list().map(\.name)) == ["base", "feature-a", "feature-b"])

        try store.restore(featureA)
        #expect(try disk() == "feature-a")
    }

    @Test("configuration changes are part of the snapshot")
    func configuration() throws {
        let snapshot = try store.create(name: "4 cpus")
        var config = try library.loadConfiguration(of: store.bundle)
        config.cpuCount = 8
        try library.save(config, to: store.bundle)

        try store.restore(snapshot)

        #expect(try library.loadConfiguration(of: store.bundle).cpuCount == 4)
    }

    @Test("restoring discards a saved state and files that did not exist yet")
    func discardsDerivedState() throws {
        let snapshot = try store.create(name: "before")
        try Data("nvram".utf8).write(to: store.bundle.efiVariableStoreURL)
        try Data("state".utf8).write(to: store.bundle.savedStateURL)

        try store.restore(snapshot)

        #expect(!store.bundle.hasSavedState())
        #expect(!FileManager.default.fileExists(atPath: store.bundle.efiVariableStoreURL.path(percentEncoded: false)))
    }

    @Test("deleting a snapshot re-attaches its children and moves HEAD to the parent")
    func deletion() throws {
        let first = try store.create(name: "first")
        let middle = try store.create(name: "middle")
        let last = try store.create(name: "last")

        try store.delete(middle)
        #expect(try store.find("last").parentID == first.id)

        try store.delete(last)
        #expect(store.head() == first.id)
        try store.delete(first)
        #expect(store.head() == nil)
        #expect(try store.list().isEmpty)
    }

    @Test("snapshots are found by name or a unique id prefix")
    func lookup() throws {
        let snapshot = try store.create(name: "clean")
        #expect(try store.find("clean") == snapshot)
        #expect(try store.find(String(snapshot.id.uuidString.prefix(8)).lowercased()) == snapshot)
        #expect(throws: SnapshotError.notFound("abc")) { try store.find("abc") }
    }

    @Test("names must be unique and non-empty")
    func names() throws {
        try store.create(name: "a")
        #expect(throws: SnapshotError.nameAlreadyUsed("a")) { try store.create(name: "a") }
        #expect(throws: SnapshotError.emptyName) { try store.create(name: "  ") }
    }

    @Test("the temporary volume reports copy-on-write support (APFS)")
    func copyOnWrite() {
        #expect(store.supportsCopyOnWrite())
    }

    @Test("an incomplete snapshot folder without metadata is ignored")
    func ignoresIncomplete() throws {
        try FileManager.default.createDirectory(
            at: store.directoryURL.appending(path: UUID().uuidString), withIntermediateDirectories: true
        )
        #expect(try store.list().isEmpty)
    }
}
