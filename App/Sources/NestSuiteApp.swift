// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestImages
import NestVirtualization
import SwiftUI

@main
struct NestSuiteApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var library = LibraryModel.live()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(Text("NestSuite"), id: "library") {
            LibraryView()
                .environment(library)
                .frame(minWidth: 760, minHeight: 480)
                .task {
                    appDelegate.library = library
                    await library.reload()
                    #if DEBUG
                        await DebugAutomation.run(library: library, openWindow: openWindow)
                    #endif
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands { LibraryCommands(library: library) }

        WindowGroup(Text("Virtual Machine"), id: "machine", for: URL.self) { $bundleURL in
            if let bundleURL {
                MachineWindow(bundleURL: bundleURL)
                    .environment(library)
            }
        }
        .defaultSize(width: 1280, height: 840)

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
            Button("New Virtual Machine…") { library.isShowingNewMachine = true }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .sidebar) {
            Button("Reload Library") {
                Task { await library.reload() }
            }
            .keyboardShortcut("r")
        }
    }
}

#if DEBUG
    /// Launch-argument automation for UI tests and documentation screenshots. Debug builds only.
    ///
    /// `-NestSuiteAutostart <machine name>` starts a machine and opens its window;
    /// `-NestSuiteInstaller <path>` attaches an installer image (must be readable by the sandbox,
    /// e.g. inside the app container). `-NestSuiteCreateCloud <image>` creates and starts a machine from
    /// a catalog cloud image (password from `-NestSuitePassword`). `-NestSuiteShowNewMachine YES` opens
    /// the “New Virtual Machine” sheet.
    @MainActor
    enum DebugAutomation {
        static func run(library: LibraryModel, openWindow: OpenWindowAction) async {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "NestSuiteShowNewMachine") {
                library.isShowingNewMachine = true
            }
            if let imageID = defaults.string(forKey: "NestSuiteCreateCloud"),
               let image = ImageCatalog.image(named: imageID)
            {
                var config = VirtualMachineConfiguration.recommended(
                    for: .linux,
                    name: image.family,
                    host: library.host
                )
                config.memorySize = .gibibytes(2)
                do {
                    let bundle = try await library.provisionMachine(
                        config, from: image, password: defaults.string(forKey: "NestSuitePassword") ?? "nestsuite-test"
                    ) { _ in }
                    let session = library.session(
                        for: bundle,
                        configuration: library.configuration(of: bundle) ?? config
                    )
                    openWindow(id: "machine", value: bundle.url)
                    await library.start(session)
                } catch {
                    library.engineError = String(describing: error)
                }
                return
            }
            guard let name = defaults.string(forKey: "NestSuiteAutostart"),
                  let entry = library.entries.first(where: {
                      if case let .machine(_, config) = $0 {
                          return config.name == name
                      }
                      return false
                  }),
                  case let .machine(bundle, configuration) = entry
            else { return }
            library.selection = entry.id
            let session = library.session(for: bundle, configuration: configuration)
            openWindow(id: "machine", value: bundle.url)
            let installer = defaults.string(forKey: "NestSuiteInstaller").map { URL(filePath: $0) }
            await library.start(session, installer: installer)
        }
    }
#endif
