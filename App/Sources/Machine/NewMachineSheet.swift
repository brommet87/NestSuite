// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestDesign
import SwiftUI
import UniformTypeIdentifiers

/// Creates a Linux virtual machine: name, installer image and resources with live validation.
///
/// Defaults come from `VirtualMachineConfiguration.recommended`, so most people only enter a name
/// and pick an installer.
struct NewMachineSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var draft: VirtualMachineConfiguration
    @State private var installer: URL?
    @State private var isPickingInstaller = false
    @State private var isCreating = false
    @State private var failure: String?
    private let host: HostCapabilities

    init(host: HostCapabilities) {
        self.host = host
        _draft = State(initialValue: .recommended(for: .linux, name: "Linux", host: host))
    }

    private var issues: [ConfigurationIssue] {
        ConfigurationValidator(host: host).issues(in: draft)
    }

    private var canCreate: Bool {
        !isCreating && !issues.contains { $0.severity == .error }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Ubuntu"))
                    LabeledContent("Installer") {
                        HStack {
                            Text(verbatim: installer?.lastPathComponent ?? "—")
                                .foregroundStyle(installer == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") { isPickingInstaller = true }
                        }
                    }
                } footer: {
                    Text(
                        // swiftlint:disable:next line_length
                        "Download an ARM64 (aarch64) installer image from your distribution, e.g. Ubuntu Server or Fedora."
                    )
                    .foregroundStyle(.secondary)
                }

                Section("Hardware") {
                    Stepper(value: $draft.cpuCount, in: host.minimumCPUCount ... host.maximumCPUCount) {
                        LabeledContent("Processors") { Text(draft.cpuCount, format: .number) }
                    }
                    Stepper(
                        value: gibibytes(\.memorySize),
                        in: 1 ... max(1, Int(host.maximumMemorySize.wholeGibibytes))
                    ) {
                        LabeledContent("Memory") { Text(verbatim: draft.memorySize.description) }
                    }
                    Stepper(value: gibibytes(\.diskSize), in: 8 ... 2048, step: 8) {
                        LabeledContent("Disk") { Text(verbatim: draft.diskSize.description) }
                    }
                }

                Section("Integration") {
                    Toggle("Shared Clipboard", isOn: $draft.isClipboardSharingEnabled)
                    Toggle("Rosetta for x86-64 Apps", isOn: $draft.isRosettaEnabled)
                        .disabled(!host.isRosettaAvailable)
                    Picker("Network", selection: $draft.network) {
                        ForEach(NetworkMode.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                }

                if !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.self) { IssueRow(issue: $0) }
                    }
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.octagon.fill").foregroundStyle(Tokens.Status.failed)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(installer == nil ? "Create" : "Create and Start") { Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding(Tokens.Spacing.large)
        }
        .frame(width: 520, height: 600)
        .navigationTitle(Text("New Virtual Machine"))
        .fileImporter(isPresented: $isPickingInstaller, allowedContentTypes: [Self.isoType]) { result in
            if case let .success(url) = result {
                installer = url
            }
        }
    }

    private static let isoType = UTType(filenameExtension: "iso") ?? .diskImage

    /// Binds a byte-count field as whole GiB for the stepper.
    private func gibibytes(_ keyPath: WritableKeyPath<VirtualMachineConfiguration, ByteCount>) -> Binding<Int> {
        Binding(
            get: { Int(draft[keyPath: keyPath].wholeGibibytes) },
            set: { draft[keyPath: keyPath] = .gibibytes(UInt64(max($0, 1))) }
        )
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundle = try await library.createMachine(draft)
            dismiss()
            guard let installer else { return }
            let session = library.session(for: bundle, configuration: draft)
            openWindow(id: "machine", value: bundle.url)
            // The importer granted access for this process; keep it while the installer is attached.
            _ = installer.startAccessingSecurityScopedResource()
            await library.start(session, installer: installer)
        } catch {
            failure = error.localizedDescription
        }
    }
}
