// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestDesign
import NestVirtualization
import SwiftUI

/// The Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .frame(width: 520, height: 360)
    }
}

struct GeneralSettingsView: View {
    private let host = HostCapabilities.current()

    var body: some View {
        Form {
            Section("This Mac") {
                LabeledContent("Processors") { Text(host.cpuCount, format: .number) }
                LabeledContent("Memory") { Text(verbatim: host.physicalMemory.description) }
                LabeledContent("Rosetta for Linux") { Text(host.isRosettaAvailable ? "Available" : "Not Installed") }
                LabeledContent("macOS Virtual Machines") {
                    Text(host.supportsMacOSGuests ? "Supported" : "Not Supported")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: Tokens.Spacing.medium) {
            BrandMark().frame(width: 72)
            Text(verbatim: "NestSuite").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.shortVersion)")
                .foregroundStyle(.secondary)
            Text("Free and open-source software under the GNU General Public License v3.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: Tokens.Size.readableWidth)
            Link("Source Code on GitHub", destination: Links.repository)
        }
        .padding(Tokens.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
}
