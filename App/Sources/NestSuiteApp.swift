// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestVirtualization
import SwiftUI

@main
struct NestSuiteApp: App {
    @State private var library = LibraryModel.live()

    var body: some Scene {
        Window(Text("NestSuite"), id: "library") {
            LibraryView()
                .environment(library)
                .frame(minWidth: 760, minHeight: 480)
                .task { await library.reload() }
        }
        .defaultSize(width: 1040, height: 680)
        .commands { LibraryCommands(library: library) }

        Settings {
            SettingsView()
        }
    }
}

/// Menu bar commands. Every action in the UI is also reachable from the menu bar with a shortcut.
struct LibraryCommands: Commands {
    let library: LibraryModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Virtual Machine…") {}
                .keyboardShortcut("n")
                .disabled(true) // Enabled with the creation assistant in 0.2 (see ROADMAP.md).
        }
        CommandGroup(after: .sidebar) {
            Button("Reload Library") {
                Task { await library.reload() }
            }
            .keyboardShortcut("r")
        }
    }
}
