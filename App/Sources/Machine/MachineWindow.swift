// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestDesign
import NestVirtualization
import SwiftUI
import Virtualization

/// The window showing a machine’s display. One window per machine, identified by its bundle URL.
struct MachineWindow: View {
    @Environment(LibraryModel.self) private var library
    let bundleURL: URL

    var body: some View {
        if let session = library.sessions[bundleURL] {
            MachineDisplay(session: session)
                .navigationTitle(Text(verbatim: session.configuration.name))
                .navigationSubtitle(Text(session.state.localizedTitle))
                .toolbar { MachineToolbar(session: session) }
        } else {
            EmptyStateView(
                title: Text("This Virtual Machine Isn’t Running"),
                message: Text("Start it from the library window.")
            ) {
                Image(systemName: "display")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } actions: {
                EmptyView()
            }
        }
    }
}

/// Shows the guest display while active, otherwise a calm placeholder that explains the state.
struct MachineDisplay: View {
    @Environment(LibraryModel.self) private var library
    let session: VirtualMachineSession

    var body: some View {
        ZStack {
            if let machine = session.machine {
                VirtualMachineDisplayView(machine: machine)
                    .accessibilityLabel(Text("Display of \(session.configuration.name)"))
            } else {
                Color.black
                VStack(spacing: Tokens.Spacing.medium) {
                    StatusBadge(state: session.state)
                        .font(.title3)
                        .colorScheme(.dark)
                    if !session.state.isActive {
                        Button("Start") { Task { await library.start(session) } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

/// `VZVirtualMachineView` in SwiftUI. Captures system keys (⌘-Tab etc.) only while focused, and lets
/// the guest resize its display with the window.
struct VirtualMachineDisplayView: NSViewRepresentable {
    let machine: VZVirtualMachine

    func makeNSView(context _: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        view.capturesSystemKeys = true
        view.automaticallyReconfiguresDisplay = true
        view.virtualMachine = machine
        return view
    }

    func updateNSView(_ view: VZVirtualMachineView, context _: Context) {
        if view.virtualMachine !== machine {
            view.virtualMachine = machine
        }
    }
}

/// Lifecycle controls, shared by the machine window and the library detail view.
struct MachineToolbar: ToolbarContent {
    @Environment(LibraryModel.self) private var library
    let session: VirtualMachineSession

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch session.state {
            case .running:
                Button {
                    Task { await library.perform { try await session.pause() } }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .help("Pause the virtual machine")
                Button {
                    Task { await library.perform { try session.requestStop() } }
                } label: {
                    Label("Shut Down", systemImage: "power")
                }
                .help("Ask the operating system to shut down")
            case .paused:
                Button {
                    Task { await library.perform { try await session.resume() } }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
            case .stopped, .failed:
                Button {
                    Task { await library.start(session) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            default:
                ProgressView().controlSize(.small)
            }
            if session.state.isActive {
                Menu {
                    Button("Force Shut Down", role: .destructive) {
                        Task { await library.perform { try await session.forceStop() } }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Force Shut Down turns the machine off immediately, like pulling the plug")
            }
        }
    }
}
