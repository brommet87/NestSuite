// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Testing
@testable import NestSuite

@MainActor
@Suite("LibraryModel")
struct LibraryModelTests {
    private let host = HostCapabilities(
        cpuCount: 8, physicalMemory: .gibibytes(16), minimumCPUCount: 1, maximumCPUCount: 8,
        minimumMemorySize: .mebibytes(128), maximumMemorySize: .gibibytes(16),
        isRosettaAvailable: true, supportsMacOSGuests: true
    )

    private func makeModel() throws -> (LibraryModel, VirtualMachineLibrary, RecordingWorkspace, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "NestSuiteTests-\(UUID().uuidString)")
        let library = VirtualMachineLibrary(rootURL: root)
        let workspace = RecordingWorkspace()
        return (LibraryModel(library: library, host: host, workspace: workspace), library, workspace, root)
    }

    @Test("an empty library shows the welcome state")
    func emptyLibrary() async throws {
        let (model, _, _, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }

        await model.reload()

        #expect(model.loadState == .loaded)
        #expect(model.isEmpty)
        #expect(model.selection == nil)
    }

    @Test("reloading selects the first machine")
    func selectsFirst() async throws {
        let (model, library, _, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = VirtualMachineConfiguration.recommended(for: .linux, name: "Alpine", host: host)
        let bundle = try library.createBundle(for: config)

        await model.reload()

        #expect(model.entries.count == 1)
        #expect(model.selection == bundle.url)
        #expect(model.selectedEntry == .machine(bundle, config))
    }

    @Test("revealing in Finder goes through the workspace")
    func reveal() async throws {
        let (model, library, workspace, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        try library.createBundle(for: .recommended(for: .linux, name: "Debian", host: host))
        await model.reload()

        let entry = try #require(model.selectedEntry)
        model.revealInFinder(entry)

        #expect(workspace.revealed == [entry.id])
    }

    @Test("a missing library folder reports a failure instead of crashing")
    func noLibrary() async {
        let model = LibraryModel(library: nil, host: host, workspace: RecordingWorkspace())
        await model.reload()
        guard case .failed = model.loadState else {
            Issue.record("expected failed state, got \(model.loadState)")
            return
        }
    }
}

@MainActor
final class RecordingWorkspace: WorkspaceActions {
    private(set) var revealed: [URL] = []

    func reveal(_ url: URL) {
        revealed.append(url)
    }
}
