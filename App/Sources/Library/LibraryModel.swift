// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import AppKit
import NestCore
import NestVirtualization
import Observation

/// The app's view of the VM library: which machines exist and which one is selected.
///
/// Main-actor isolated because SwiftUI reads it. File-system work runs off the main actor, so a
/// slow disk never freezes the window.
@MainActor
@Observable
final class LibraryModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var entries: [LibraryEntry] = []
    private(set) var loadState: LoadState = .idle
    var selection: LibraryEntry.ID?
    let host: HostCapabilities

    private let library: VirtualMachineLibrary?
    private let workspace: WorkspaceActions

    init(library: VirtualMachineLibrary?, host: HostCapabilities, workspace: WorkspaceActions) {
        self.library = library
        self.host = host
        self.workspace = workspace
    }

    /// The production configuration: the default library folder and the real host.
    static func live() -> LibraryModel {
        let library = (try? VirtualMachineLibrary.defaultRootURL()).map(VirtualMachineLibrary.init(rootURL:))
        return LibraryModel(library: library, host: .current(), workspace: SystemWorkspace())
    }

    var selectedEntry: LibraryEntry? {
        entries.first { $0.id == selection }
    }

    var isEmpty: Bool {
        loadState == .loaded && entries.isEmpty
    }

    func reload() async {
        guard let library else {
            loadState = .failed(message: String(localized: "The library folder could not be created."))
            return
        }
        loadState = .loading
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try library.entries() }.value
            entries = loaded
            loadState = .loaded
            // Keep the selection valid: fall back to the first entry if the selected one vanished.
            if selectedEntry == nil {
                selection = entries.first?.id
            }
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }

    func revealInFinder(_ entry: LibraryEntry) {
        workspace.reveal(entry.id)
    }

    /// Moves the bundle to the Trash (recoverable) and reloads.
    func moveToTrash(_ entry: LibraryEntry) async {
        guard let library else { return }
        let bundle = VirtualMachineBundle(url: entry.id)
        do {
            try await Task.detached { try library.moveToTrash(bundle) }.value
        } catch {
            loadState = .failed(message: error.localizedDescription)
            return
        }
        if selection == entry.id {
            selection = nil
        }
        await reload()
    }

    func openLibraryFolder() {
        guard let library else { return }
        workspace.reveal(library.rootURL)
    }
}

/// Side effects on the Mac's desktop, behind a protocol so tests can verify them without Finder.
@MainActor
protocol WorkspaceActions {
    func reveal(_ url: URL)
}

struct SystemWorkspace: WorkspaceActions {
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
