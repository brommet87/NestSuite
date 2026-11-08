// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestDesign
import SwiftUI

/// The main window: machines in the sidebar, the selected machine on the right.
struct LibraryView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        NavigationSplitView {
            List(selection: $library.selection) {
                // No header over an empty list: the welcome screen explains the empty state.
                if !library.entries.isEmpty {
                    Section("Virtual Machines") {
                        ForEach(library.entries) { entry in
                            LibrarySidebarRow(entry: entry)
                                .tag(entry.id)
                                .contextMenu { EntryContextMenu(entry: entry) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            .overlay {
                if library.loadState == .loading, library.entries.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Creation assistant arrives in 0.2 (see ROADMAP.md).
                } label: {
                    Label("New Virtual Machine", systemImage: "plus")
                }
                .help("Creating virtual machines arrives in version 0.2.")
                .disabled(true)
            }
        }
        .navigationTitle(navigationTitle)
    }

    @ViewBuilder
    private var detail: some View {
        switch (library.loadState, library.selectedEntry) {
        case let (.failed(message), _):
            LibraryErrorView(message: message)
        case let (_, .some(.machine(_, configuration))):
            MachineDetailView(configuration: configuration)
        case let (_, .some(.damaged(bundle, error))):
            DamagedBundleView(bundle: bundle, error: error)
        case (.loaded, .none) where library.isEmpty:
            WelcomeView()
        default:
            Text("Select a virtual machine")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var navigationTitle: Text {
        switch library.selectedEntry {
        case let .machine(_, configuration): Text(verbatim: configuration.name)
        case let .damaged(bundle, _): Text(verbatim: bundle.url.deletingPathExtension().lastPathComponent)
        case nil: Text(verbatim: "NestSuite")
        }
    }
}

/// One row in the sidebar.
struct LibrarySidebarRow: View {
    let entry: LibraryEntry

    var body: some View {
        switch entry {
        case let .machine(_, configuration):
            Label {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                    Text(verbatim: configuration.name)
                        .lineLimit(1)
                    StatusBadge(state: .stopped)
                        .font(.caption)
                }
            } icon: {
                GuestIcon(guest: configuration.guest)
            }
        case let .damaged(bundle, _):
            Label {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxSmall) {
                    Text(verbatim: bundle.url.deletingPathExtension().lastPathComponent)
                        .lineLimit(1)
                    Text("Needs attention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: Tokens.Size.sidebarIcon, height: Tokens.Size.sidebarIcon)
                    .background(Tokens.Status.failed.gradient, in: .rect(cornerRadius: Tokens.Radius.small))
            }
            .accessibilityHint(Text("This virtual machine could not be read."))
        }
    }
}

/// Context menu actions shared by sidebar rows.
struct EntryContextMenu: View {
    @Environment(LibraryModel.self) private var library
    let entry: LibraryEntry

    var body: some View {
        Button("Show in Finder") { library.revealInFinder(entry) }
        Divider()
        Button("Move to Trash", role: .destructive) {
            Task { await library.moveToTrash(entry) }
        }
    }
}

/// The guest OS as a compact, recognizable icon.
struct GuestIcon: View {
    let guest: GuestOperatingSystem

    var body: some View {
        Image(systemName: guest.symbolName)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: Tokens.Size.sidebarIcon, height: Tokens.Size.sidebarIcon)
            .background(guest.tileColor.gradient, in: .rect(cornerRadius: Tokens.Radius.small))
            .accessibilityLabel(Text(guest.localizedName))
    }
}

extension GuestOperatingSystem {
    var symbolName: String {
        switch self {
        case .linux: "terminal.fill"
        case .macOS: "macwindow"
        }
    }

    var tileColor: Color {
        switch self {
        case .linux: Tokens.Brand.indigo
        case .macOS: Tokens.Brand.azure
        }
    }

    var localizedName: LocalizedStringResource {
        switch self {
        case .linux: "Linux"
        case .macOS: "macOS"
        }
    }
}
