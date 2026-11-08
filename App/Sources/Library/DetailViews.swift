// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestDesign
import SwiftUI

/// First-run screen: explains what NestSuite does and what comes next.
struct WelcomeView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        EmptyStateView(
            title: Text("Welcome to NestSuite"),
            message: Text(
                // swiftlint:disable:next line_length
                "Run Linux and macOS side by side with your Mac apps. Creating virtual machines arrives in version 0.2 — this preview sets up your library."
            )
        ) {
            BrandMark()
        } actions: {
            HStack(spacing: Tokens.Spacing.medium) {
                Button("Open Library Folder") { library.openLibraryFolder() }
                Link("View Roadmap", destination: Links.roadmap)
            }
        }
    }
}

/// Overview of a machine's configuration.
struct MachineDetailView: View {
    @Environment(LibraryModel.self) private var library
    let configuration: VirtualMachineConfiguration

    var body: some View {
        let issues = ConfigurationValidator(host: library.host).issues(in: configuration)
        Form {
            Section {
                LabeledContent("Operating System") { Text(configuration.guest.localizedName) }
                LabeledContent("Status") { StatusBadge(state: .stopped) }
            }
            Section("Hardware") {
                LabeledContent("Processors") { Text(configuration.cpuCount, format: .number) }
                LabeledContent("Memory") { Text(verbatim: configuration.memorySize.description) }
                // Same binary units as memory, so an 80 GB disk reads "80 GB", not "85.9 GB".
                LabeledContent("Disk") { Text(verbatim: configuration.diskSize.description) }
                LabeledContent("Display") {
                    Text(verbatim: "\(configuration.display.widthInPixels) × \(configuration.display.heightInPixels)")
                }
            }
            Section("Integration") {
                LabeledContent("Network") { Text(configuration.network.localizedName) }
                LabeledContent("Shared Clipboard") { OnOffText(isOn: configuration.isClipboardSharingEnabled) }
                LabeledContent("Shared Folders") { Text(configuration.sharedFolders.count, format: .number) }
                if configuration.guest.supportsRosetta {
                    LabeledContent("Rosetta for x86-64 Apps") { OnOffText(isOn: configuration.isRosettaEnabled) }
                }
            }
            if !issues.isEmpty {
                Section("Issues") {
                    ForEach(issues, id: \.self) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A bundle that could not be read: explains why and offers the safe ways out.
struct DamagedBundleView: View {
    @Environment(LibraryModel.self) private var library
    let bundle: VirtualMachineBundle
    let error: VirtualMachineLibraryError

    var body: some View {
        EmptyStateView(
            title: Text("This Virtual Machine Can’t Be Opened"),
            message: Text(verbatim: error.userMessage)
        ) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Tokens.Status.failed)
                .padding(Tokens.Spacing.large)
                .accessibilityHidden(true)
        } actions: {
            HStack(spacing: Tokens.Spacing.medium) {
                Button("Show in Finder") { library.revealInFinder(.damaged(bundle, error)) }
                Button("Move to Trash", role: .destructive) {
                    Task { await library.moveToTrash(.damaged(bundle, error)) }
                }
            }
        }
    }
}

struct LibraryErrorView: View {
    @Environment(LibraryModel.self) private var library
    let message: String

    var body: some View {
        EmptyStateView(title: Text("The Library Couldn’t Be Loaded"), message: Text(verbatim: message)) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } actions: {
            Button("Try Again") { Task { await library.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct IssueRow: View {
    let issue: ConfigurationIssue

    var body: some View {
        Label {
            Text(issue.localizedDescription)
        } icon: {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Tokens.Status.failed : Tokens.Status.paused)
        }
    }
}

struct OnOffText: View {
    let isOn: Bool

    var body: some View {
        Text(isOn ? "On" : "Off")
    }
}

enum Links {
    static let repository = URL(string: "https://github.com/brommet87/NestSuite") ?? URL(filePath: "/")
    static let roadmap = URL(string: "https://github.com/brommet87/NestSuite/blob/main/ROADMAP.md") ?? repository
}
