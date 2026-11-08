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
    /// Running or recently used machines, by bundle URL. Sessions outlive selection changes, so a
    /// machine keeps running when you select another one.
    /// Not observed itself (views observe each session’s `state`), so creating a session lazily while
    /// a view renders doesn't invalidate the whole library.
    @ObservationIgnored private(set) var sessions: [URL: VirtualMachineSession] = [:]
    /// Whether the “New Virtual Machine” sheet is shown (menu command and toolbar share it).
    var isShowingNewMachine = false
    /// The last start/stop error, shown as an alert.
    var engineError: String?
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
        guard !state(of: entry).isActive else {
            engineError = String(localized: "Shut down the virtual machine before moving it to the Trash.")
            return
        }
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

    // MARK: - Machines

    /// The session for a machine, created on first use.
    func session(
        for bundle: VirtualMachineBundle,
        configuration: VirtualMachineConfiguration
    ) -> VirtualMachineSession {
        if let existing = sessions[bundle.url] {
            return existing
        }
        let session = VirtualMachineSession(bundle: bundle, configuration: configuration)
        sessions[bundle.url] = session
        return session
    }

    func state(of entry: LibraryEntry) -> VirtualMachineState {
        sessions[entry.id]?.state ?? .stopped
    }

    /// Starts a machine, optionally from an installer image, and reports failures as an alert.
    func start(_ session: VirtualMachineSession, installer: URL? = nil) async {
        do {
            try await session.start(bootMedia: installer.map(BootMedia.installer) ?? .none)
        } catch {
            engineError = (error as? EngineError)?.description ?? error.localizedDescription
        }
    }

    func perform(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
        } catch {
            engineError = (error as? EngineError)?.description ?? error.localizedDescription
        }
    }

    /// Creates a new machine and selects it.
    func createMachine(_ configuration: VirtualMachineConfiguration) async throws -> VirtualMachineBundle {
        guard let library else { throw VirtualMachineLibraryError.configurationMissing(URL(filePath: "/")) }
        let bundle = try await Task.detached { try library.createBundle(for: configuration) }.value
        await reload()
        selection = bundle.url
        return bundle
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
