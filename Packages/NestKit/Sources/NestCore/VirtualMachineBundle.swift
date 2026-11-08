// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// A virtual machine on disk: a `.nestvm` directory that contains everything the machine needs.
///
/// Keeping one self-contained bundle per machine means users can move, back up or delete a VM in
/// Finder like any document, and Time Machine handles it correctly.
///
/// ```
/// Ubuntu.nestvm/
/// ├── config.json          VirtualMachineConfiguration (human-readable)
/// ├── Disk.img             raw sparse disk image (APFS keeps it small)
/// ├── MachineIdentifier    stable identity across launches
/// ├── NVRAM                EFI variable store (Linux)
/// ├── AuxiliaryStorage     boot data (macOS)
/// ├── HardwareModel        hardware model (macOS)
/// └── SavedState.vzvmsave  suspended state, only while suspended
/// ```
public struct VirtualMachineBundle: Hashable, Sendable {
    public static let pathExtension = "nestvm"

    public let url: URL

    /// The URL is normalized (symlinks resolved, directory form), so the same bundle always compares
    /// equal regardless of how its path was obtained (e.g. `/var` vs. `/private/var`).
    public init(url: URL) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        self.url = URL(filePath: resolved.path(percentEncoded: false), directoryHint: .isDirectory)
    }

    public var configurationURL: URL {
        url.appending(path: "config.json")
    }

    public var diskImageURL: URL {
        url.appending(path: "Disk.img")
    }

    public var machineIdentifierURL: URL {
        url.appending(path: "MachineIdentifier")
    }

    public var efiVariableStoreURL: URL {
        url.appending(path: "NVRAM")
    }

    public var auxiliaryStorageURL: URL {
        url.appending(path: "AuxiliaryStorage")
    }

    public var hardwareModelURL: URL {
        url.appending(path: "HardwareModel")
    }

    /// cloud-init seed volume for machines created from cloud images; attached read-only when present.
    public var cloudInitSeedURL: URL {
        url.appending(path: "CloudInit.img")
    }

    /// Present once the guest reported that first-boot provisioning finished.
    public var provisionedMarkerURL: URL {
        url.appending(path: ".provisioned")
    }

    public var savedStateURL: URL {
        url.appending(path: "SavedState.vzvmsave")
    }

    public func hasSavedState(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: savedStateURL.path(percentEncoded: false))
    }
}

/// Errors from reading or writing VM bundles. Structured for localized presentation in the UI.
public enum VirtualMachineLibraryError: Error, Hashable, Sendable {
    case configurationMissing(URL)
    case configurationUnreadable(URL, reason: String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case bundleAlreadyExists(URL)
    /// Machine names are unique (case-insensitive), so commands and Nestfiles can refer to them.
    case nameInUse(String)
}

/// One entry in the library: either a readable machine or a damaged bundle the user should know about.
///
/// Damaged bundles are listed instead of hidden, so a broken config never makes a VM "disappear".
public enum LibraryEntry: Hashable, Sendable, Identifiable {
    case machine(VirtualMachineBundle, VirtualMachineConfiguration)
    case damaged(VirtualMachineBundle, VirtualMachineLibraryError)

    public var id: URL {
        switch self {
        case let .machine(bundle, _), let .damaged(bundle, _): bundle.url
        }
    }
}

/// Reads and writes VM bundles in a directory (by default the app's Application Support folder).
public struct VirtualMachineLibrary: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The app’s bundle identifier; its sandbox container holds the default library.
    public static let appBundleIdentifier = "io.github.brommet87.NestSuite"

    /// The library used by the sandboxed app, as seen from an unsandboxed process such as `nestctl`.
    public static func appLibraryURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(
            path: "Library/Containers/\(appBundleIdentifier)/Data/Library/Application Support/NestSuite/Machines",
            directoryHint: .isDirectory
        )
    }

    /// `~/Library/Application Support/NestSuite/Machines` (inside the sandbox container when sandboxed).
    public static func defaultRootURL(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "NestSuite/Machines", directoryHint: .isDirectory)
    }

    /// All bundles in the library, sorted by machine name (damaged bundles by file name).
    public func entries(fileManager: FileManager = .default) throws -> [LibraryEntry] {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == VirtualMachineBundle.pathExtension }
            .map { url in
                let bundle = VirtualMachineBundle(url: url)
                do {
                    return try .machine(bundle, loadConfiguration(of: bundle, fileManager: fileManager))
                } catch let error as VirtualMachineLibraryError {
                    return .damaged(bundle, error)
                } catch {
                    return .damaged(bundle, .configurationUnreadable(url, reason: error.localizedDescription))
                }
            }
            .sorted { sortKey(for: $0).localizedStandardCompare(sortKey(for: $1)) == .orderedAscending }
    }

    /// Creates a new, empty bundle for `configuration`. The disk image is created later by the
    /// virtualization layer, because its format depends on the engine.
    @discardableResult
    public func createBundle(
        for configuration: VirtualMachineConfiguration,
        fileManager: FileManager = .default
    ) throws -> VirtualMachineBundle {
        try ensureNameAvailable(configuration.name, fileManager: fileManager)
        let bundle = VirtualMachineBundle(url: uniqueBundleURL(for: configuration.name, fileManager: fileManager))
        guard !fileManager.fileExists(atPath: bundle.url.path(percentEncoded: false)) else {
            throw VirtualMachineLibraryError.bundleAlreadyExists(bundle.url)
        }
        try fileManager.createDirectory(at: bundle.url, withIntermediateDirectories: true)
        try save(configuration, to: bundle)
        return bundle
    }

    /// Whether a machine with this name exists (case-insensitive, ignoring surrounding spaces).
    public func isNameInUse(_ name: String, fileManager: FileManager = .default) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = (try? entries(fileManager: fileManager)) ?? []
        return entries.contains { entry in
            if case let .machine(_, configuration) = entry {
                return configuration.name.caseInsensitiveCompare(wanted) == .orderedSame
            }
            return false
        }
    }

    func ensureNameAvailable(_ name: String, fileManager: FileManager) throws {
        if isNameInUse(name, fileManager: fileManager) {
            throw VirtualMachineLibraryError.nameInUse(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Atomically writes the configuration, so a crash never leaves a half-written `config.json`.
    public func save(_ configuration: VirtualMachineConfiguration, to bundle: VirtualMachineBundle) throws {
        try Self.makeEncoder().encode(configuration).write(to: bundle.configurationURL, options: .atomic)
    }

    public func loadConfiguration(
        of bundle: VirtualMachineBundle,
        fileManager: FileManager = .default
    ) throws -> VirtualMachineConfiguration {
        guard fileManager.fileExists(atPath: bundle.configurationURL.path(percentEncoded: false)) else {
            // Reported with the bundle's normalized URL so callers can match it to the entry.
            throw VirtualMachineLibraryError.configurationMissing(bundle.url)
        }
        let data = try Data(contentsOf: bundle.configurationURL)
        let decoder = Self.makeDecoder()

        // Check the schema version first, so a newer file gives a clear message instead of a
        // generic decoding error.
        struct VersionProbe: Decodable { let schemaVersion: Int }
        if let probe = try? decoder.decode(VersionProbe.self, from: data),
           probe.schemaVersion > VirtualMachineConfiguration.currentSchemaVersion
        {
            throw VirtualMachineLibraryError.unsupportedSchemaVersion(
                found: probe.schemaVersion,
                supported: VirtualMachineConfiguration.currentSchemaVersion
            )
        }
        do {
            return try decoder.decode(VirtualMachineConfiguration.self, from: data)
        } catch {
            throw VirtualMachineLibraryError.configurationUnreadable(bundle.url, reason: String(describing: error))
        }
    }

    /// Moves the bundle to the Trash, so deleting a VM can be undone in Finder.
    public func moveToTrash(_ bundle: VirtualMachineBundle, fileManager: FileManager = .default) throws {
        try fileManager.trashItem(at: bundle.url, resultingItemURL: nil)
    }

    /// Deletes the bundle immediately. Only for explicit requests (e.g. `nestctl rm --force` for
    /// disposable CI machines); the app always uses ``moveToTrash(_:fileManager:)``.
    public func removePermanently(_ bundle: VirtualMachineBundle, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: bundle.url)
    }

    /// Finds a machine by name (case-insensitive), falling back to the bundle’s file name.
    public func entry(named name: String, fileManager: FileManager = .default) throws -> LibraryEntry? {
        let entries = try entries(fileManager: fileManager)
        let byName = entries.first { entry in
            if case let .machine(_, configuration) = entry {
                return configuration.name.caseInsensitiveCompare(name) == .orderedSame
            }
            return false
        }
        return byName ?? entries.first {
            $0.id.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Creates a linked clone: an independent machine that initially shares all disk blocks with the
    /// source.
    ///
    /// On APFS, `FileManager.copyItem` clones files copy-on-write, so even a 64 GB disk is cloned in
    /// milliseconds and only diverging blocks use space. The clone gets a new identity: new `id`,
    /// name and creation date; the machine identifier and any saved state are dropped, because two
    /// machines must never share an identity and a saved state belongs to the exact source machine.
    @discardableResult
    public func clone(
        _ source: VirtualMachineBundle,
        as name: String,
        fileManager: FileManager = .default
    ) throws -> (bundle: VirtualMachineBundle, configuration: VirtualMachineConfiguration) {
        let sourceConfiguration = try loadConfiguration(of: source, fileManager: fileManager)
        try ensureNameAvailable(name, fileManager: fileManager)
        let target = VirtualMachineBundle(url: uniqueBundleURL(for: name, fileManager: fileManager))
        try fileManager.copyItem(at: source.url, to: target.url)

        do {
            for derived in [target.machineIdentifierURL, target.savedStateURL]
                where fileManager.fileExists(atPath: derived.path(percentEncoded: false))
            {
                try fileManager.removeItem(at: derived)
            }
            var configuration = VirtualMachineConfiguration(
                name: name,
                guest: sourceConfiguration.guest,
                cpuCount: sourceConfiguration.cpuCount,
                memorySize: sourceConfiguration.memorySize,
                diskSize: sourceConfiguration.diskSize,
                display: sourceConfiguration.display,
                network: sourceConfiguration.network,
                sharedFolders: sourceConfiguration.sharedFolders,
                isClipboardSharingEnabled: sourceConfiguration.isClipboardSharingEnabled,
                isRosettaEnabled: sourceConfiguration.isRosettaEnabled
            )
            configuration.schemaVersion = sourceConfiguration.schemaVersion
            try save(configuration, to: target)
            return (target, configuration)
        } catch {
            // Never leave a half-initialized clone behind.
            try? fileManager.removeItem(at: target.url)
            throw error
        }
    }

    // MARK: - Coding

    /// Dates are written as plain ISO 8601 (whole seconds, see `VirtualMachineConfiguration.createdAt`).
    private static let dateFormat = Date.ISO8601FormatStyle()
    private static let fractionalDateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateFormat))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            // Accept fractional seconds too, so hand-edited files still load.
            if let date = try? dateFormat.parse(text) {
                return date
            }
            if let date = try? fractionalDateFormat.parse(text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(text)")
        }
        return decoder
    }

    // MARK: - Private

    private func sortKey(for entry: LibraryEntry) -> String {
        switch entry {
        case let .machine(_, configuration): configuration.name
        case let .damaged(bundle, _): bundle.url.deletingPathExtension().lastPathComponent
        }
    }

    /// `Ubuntu.nestvm`, then `Ubuntu 2.nestvm`, … Names are sanitized for the file system.
    func uniqueBundleURL(for name: String, fileManager: FileManager) -> URL {
        let base = Self.sanitizedFileName(name)
        var candidate = rootURL.appending(path: "\(base).\(VirtualMachineBundle.pathExtension)")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = rootURL.appending(path: "\(base) \(counter).\(VirtualMachineBundle.pathExtension)")
            counter += 1
        }
        return candidate
    }

    static func sanitizedFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Virtual Machine" : cleaned
    }
}
