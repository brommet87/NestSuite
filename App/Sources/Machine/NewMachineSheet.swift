// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import NestDesign
import NestImages
import SwiftUI
import UniformTypeIdentifiers

/// Creates a Linux virtual machine from a ready-made cloud image (default), a distribution’s installer,
/// or your own ISO file — with live validation and download progress.
struct NewMachineSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case cloud
        case installer
        case file

        var id: Self {
            self
        }
    }

    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var draft: VirtualMachineConfiguration
    @State private var source: Source = .cloud
    @State private var cloudImageID = ImageCatalog.image(named: "ubuntu-24.04")?.id ?? ""
    @State private var installerImageID = ImageCatalog.image(named: "debian-13-netinst")?.id ?? ""
    @State private var installerFile: URL?
    @State private var password = ""
    @State private var isPickingFile = false
    @State private var progress: Double?
    @State private var phase: String?
    @State private var failure: String?
    private let host: HostCapabilities

    init(host: HostCapabilities) {
        self.host = host
        _draft = State(initialValue: .recommended(for: .linux, name: "Ubuntu", host: host))
    }

    private var issues: [ConfigurationIssue] {
        ConfigurationValidator(host: host).issues(in: draft)
    }

    private var selectedCloudImage: CatalogImage? {
        ImageCatalog.image(named: cloudImageID)
    }

    private var selectedInstaller: CatalogImage? {
        ImageCatalog.image(named: installerImageID)
    }

    private var nameInUse: Bool {
        library.isNameInUse(draft.name)
    }

    private var canCreate: Bool {
        guard progress == nil, !nameInUse, !issues.contains(where: { $0.severity == .error }) else { return false }
        switch source {
        case .cloud: return selectedCloudImage != nil && password.count >= 8
        case .installer: return selectedInstaller != nil
        case .file: return installerFile != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                sourceSection
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Ubuntu"))
                    if source == .cloud {
                        LabeledContent("User") { Text(verbatim: CloudInitSeed.sanitizedUserName(NSUserName())) }
                        SecureField("Password", text: $password, prompt: Text("At least 8 characters"))
                    }
                } footer: {
                    if source == .cloud {
                        Text("You log in with this user and password. The password is stored only as a hash.")
                            .foregroundStyle(.secondary)
                    }
                }
                hardwareSection
                integrationSection
                if !issues.isEmpty || nameInUse {
                    Section {
                        if nameInUse {
                            Label("A virtual machine with this name already exists.", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(Tokens.Status.failed)
                        }
                        ForEach(issues, id: \.self) { IssueRow(issue: $0) }
                    }
                }
                if let failure {
                    Section { Label(failure, systemImage: "xmark.octagon.fill").foregroundStyle(Tokens.Status.failed) }
                }
            }
            .formStyle(.grouped)
            .disabled(progress != nil)

            Divider()
            footer
        }
        .frame(width: 560, height: 600)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [UTType(filenameExtension: "iso") ?? .diskImage]
        ) {
            if case let .success(url) = $0 {
                installerFile = url
            }
        }
        .onChange(of: cloudImageID) { _, _ in suggestName() }
        .onChange(of: installerImageID) { _, _ in suggestName() }
        .onChange(of: source) { _, _ in suggestName() }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            Picker("Start From", selection: $source) {
                Text("Ready-Made System").tag(Source.cloud)
                Text("Installer").tag(Source.installer)
                Text("ISO File").tag(Source.file)
            }
            .pickerStyle(.segmented)
            switch source {
            case .cloud:
                catalogPicker(selection: $cloudImageID, kind: .cloud)
            case .installer:
                catalogPicker(selection: $installerImageID, kind: .installer)
            case .file:
                LabeledContent("ISO File") {
                    HStack {
                        Text(verbatim: installerFile?.lastPathComponent ?? "—")
                            .foregroundStyle(installerFile == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { isPickingFile = true }
                    }
                }
            }
        } footer: {
            Group {
                switch source {
                case .cloud:
                    Text("Starts in about a minute, already set up with your user and shared folders.")
                case .installer:
                    Text(
                        // swiftlint:disable:next line_length
                        "Downloads the distribution’s official installer. You install the system in the machine’s window."
                    )
                case .file:
                    Text("Any ARM64 (aarch64) installer image.")
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func catalogPicker(selection: Binding<String>, kind: CatalogImage.Kind) -> some View {
        Picker("System", selection: selection) {
            ForEach(ImageCatalog.images(of: kind)) { image in
                Text(verbatim: "\(image.displayName)  ·  ≈ \(image.downloadSize)").tag(image.id)
            }
        }
    }

    private var hardwareSection: some View {
        Section("Hardware") {
            StepperRow("Processors", value: $draft.cpuCount, in: host.minimumCPUCount ... host.maximumCPUCount) {
                Text(draft.cpuCount, format: .number)
            }
            StepperRow(
                "Memory",
                value: gibibytes(\.memorySize),
                in: 1 ... max(1, Int(host.maximumMemorySize.wholeGibibytes))
            ) {
                Text(verbatim: draft.memorySize.description)
            }
            StepperRow("Disk", value: gibibytes(\.diskSize), in: 8 ... 2048, step: 8) {
                Text(verbatim: draft.diskSize.description)
            }
        }
    }

    private var integrationSection: some View {
        Section("Integration") {
            Toggle("Shared Clipboard", isOn: $draft.isClipboardSharingEnabled)
            Toggle("Rosetta for x86-64 Apps", isOn: $draft.isRosettaEnabled)
                .disabled(!host.isRosettaAvailable)
            Picker("Network", selection: $draft.network) {
                ForEach(NetworkMode.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Tokens.Spacing.medium) {
            if let progress, let phase {
                ProgressView(value: progress) { Text(verbatim: phase).font(.callout) }
                    .frame(maxWidth: 280)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(progress != nil)
            Button("Create and Start") { Task { await create() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
        }
        .padding(Tokens.Spacing.large)
    }

    // MARK: - Actions

    /// Suggests a name from the chosen distribution until the user types their own.
    private func suggestName() {
        let families = ImageCatalog.all.map(\.family) + ["Linux"]
        guard families.contains(draft.name) else { return }
        draft.name = switch source {
        case .cloud: selectedCloudImage?.family ?? "Linux"
        case .installer: selectedInstaller?.family ?? "Linux"
        case .file: "Linux"
        }
    }

    private func gibibytes(_ keyPath: WritableKeyPath<VirtualMachineConfiguration, ByteCount>) -> Binding<Int> {
        Binding(
            get: { Int(draft[keyPath: keyPath].wholeGibibytes) },
            set: { draft[keyPath: keyPath] = .gibibytes(UInt64(max($0, 1))) }
        )
    }

    private func create() async {
        failure = nil
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let report: @Sendable (Double) -> Void = { value in Task { @MainActor in progress = value } }
        progress = 0
        defer {
            progress = nil
            phase = nil
        }
        do {
            let bundle: VirtualMachineBundle
            var installer: URL?
            switch source {
            case .cloud:
                guard let image = selectedCloudImage else { return }
                phase = String(localized: "Downloading and verifying \(image.displayName)…")
                bundle = try await library.provisionMachine(draft, from: image, password: password, progress: report)
            case .installer:
                guard let image = selectedInstaller else { return }
                phase = String(localized: "Downloading and verifying \(image.displayName)…")
                installer = try await library.prepareInstaller(image, progress: report)
                bundle = try await library.createMachine(draft)
            case .file:
                installer = installerFile
                _ = installerFile?.startAccessingSecurityScopedResource()
                bundle = try await library.createMachine(draft)
            }
            let configuration = library.configuration(of: bundle) ?? draft
            let session = library.session(for: bundle, configuration: configuration)
            dismiss()
            openWindow(id: "machine", value: bundle.url)
            await library.start(session, installer: installer)
        } catch {
            failure = (error as? ImageError)?.description ?? error.localizedDescription
        }
    }
}

/// A settings row with the value right-aligned next to its stepper, as in System Settings.
struct StepperRow<Value: View>: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let display: Value

    init(
        _ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
        @ViewBuilder display: () -> Value
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.display = display()
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Tokens.Spacing.small) {
                display.monospacedDigit()
                Stepper(title, value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}
