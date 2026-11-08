// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// A saved point-in-time copy of a stopped machine’s disk and firmware state.
public struct Snapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var note: String?
    public let createdAt: Date
    /// The snapshot this one was taken from (`nil` for the first). Snapshots form a tree, so you can
    /// restore an older snapshot, change things and take a new one — a branch, like in Git.
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, note: String? = nil, createdAt: Date = .now, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        self.parentID = parentID
    }
}

public enum SnapshotError: Error, Hashable, Sendable {
    case notFound(String)
    case nameAlreadyUsed(String)
    case emptyName
}

/// Snapshots of one VM bundle, stored inside it:
///
/// ```
/// Ubuntu.nestvm/Snapshots/
/// ├── HEAD                     id of the snapshot the current state descends from
/// └── 4F1C…/
///     ├── snapshot.json        Snapshot metadata
///     ├── config.json          configuration at that time
///     ├── Disk.img             APFS clone (copy-on-write, no extra space until blocks change)
///     ├── NVRAM / AuxiliaryStorage / HardwareModel   when present
/// ```
///
/// The machine must be stopped while snapshots are taken or restored; the virtualization layer
/// enforces this. A saved (suspended) state is never part of a snapshot and is discarded on restore,
/// because it only matches the exact disk it was saved with.
public struct SnapshotStore: Sendable {
    public let bundle: VirtualMachineBundle

    public init(bundle: VirtualMachineBundle) {
        self.bundle = bundle
    }

    var directoryURL: URL {
        bundle.url.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    var headURL: URL {
        directoryURL.appending(path: "HEAD")
    }

    /// Files that make up the machine state. The machine identifier is part of the machine’s identity,
    /// not its state, and stays untouched.
    var stateFiles: [URL] {
        [
            bundle.configurationURL,
            bundle.diskImageURL,
            bundle.efiVariableStoreURL,
            bundle.auxiliaryStorageURL,
            bundle.hardwareModelURL,
        ]
    }

    /// Whether the volume clones files copy-on-write (APFS). Without it, snapshots are full copies:
    /// they still work but take time and space, and tools should say so.
    public func supportsCopyOnWrite() -> Bool {
        (try? bundle.url.resourceValues(forKeys: [.volumeSupportsFileCloningKey]).volumeSupportsFileCloning) == true
    }

    /// The snapshot the current state descends from.
    public func head(fileManager: FileManager = .default) -> UUID? {
        guard let text = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        return UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// All snapshots, oldest first.
    public func list(fileManager: FileManager = .default) throws -> [Snapshot] {
        guard fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else { return [] }
        let decoder = VirtualMachineLibrary.makeDecoder()
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        .compactMap { folder -> Snapshot? in
            let metadata = folder.appending(path: "snapshot.json")
            guard let data = try? Data(contentsOf: metadata) else { return nil }
            return try decoder.decode(Snapshot.self, from: data)
        }
        .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
    }

    /// Finds a snapshot by exact name, full id or unique id prefix (like a short Git hash).
    public func find(_ reference: String, fileManager: FileManager = .default) throws -> Snapshot {
        let snapshots = try list(fileManager: fileManager)
        if let byName = snapshots.first(where: { $0.name == reference }) {
            return byName
        }
        let prefix = reference.lowercased()
        let byID = snapshots.filter { $0.id.uuidString.lowercased().hasPrefix(prefix) }
        guard prefix.count >= 4, byID.count == 1,
              let match = byID.first else { throw SnapshotError.notFound(reference) }
        return match
    }

    /// Takes a snapshot of the current state.
    @discardableResult
    public func create(name: String, note: String? = nil, fileManager: FileManager = .default) throws -> Snapshot {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SnapshotError.emptyName }
        guard try !list(fileManager: fileManager).contains(where: { $0.name == trimmed }) else {
            throw SnapshotError.nameAlreadyUsed(trimmed)
        }

        let snapshot = Snapshot(name: trimmed, note: note, parentID: head(fileManager: fileManager))
        let folder = directoryURL.appending(path: snapshot.id.uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            for file in stateFiles where fileManager.fileExists(atPath: file.path(percentEncoded: false)) {
                try fileManager.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
            }
            // Metadata last: a folder without snapshot.json is ignored, so a crash mid-copy is harmless.
            try VirtualMachineLibrary.makeEncoder().encode(snapshot)
                .write(to: folder.appending(path: "snapshot.json"), options: .atomic)
            try writeHead(snapshot.id)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return snapshot
    }

    /// Replaces the current state with the snapshot’s. Changes since then are discarded.
    public func restore(_ snapshot: Snapshot, fileManager: FileManager = .default) throws {
        let folder = directoryURL.appending(path: snapshot.id.uuidString, directoryHint: .isDirectory)
        // Stage all files first, then swap, so a failure never leaves a mix of old and new files.
        let staging = directoryURL.appending(path: ".restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for file in stateFiles {
            let source = folder.appending(path: file.lastPathComponent)
            if fileManager.fileExists(atPath: source.path(percentEncoded: false)) {
                try fileManager.copyItem(at: source, to: staging.appending(path: file.lastPathComponent))
            }
        }
        for file in stateFiles {
            let staged = staging.appending(path: file.lastPathComponent)
            if fileManager.fileExists(atPath: staged.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(file, withItemAt: staged)
            } else if fileManager.fileExists(atPath: file.path(percentEncoded: false)) {
                try fileManager.removeItem(at: file) // did not exist when the snapshot was taken
            }
        }
        if bundle.hasSavedState(fileManager: fileManager) {
            try fileManager.removeItem(at: bundle.savedStateURL)
        }
        try writeHead(snapshot.id)
    }

    /// Deletes a snapshot. Its children are re-attached to its parent, so the tree stays connected.
    public func delete(_ requested: Snapshot, fileManager: FileManager = .default) throws {
        // Use the stored metadata, not the caller's copy: its parent may have changed since it was
        // read (e.g. when the parent itself was deleted).
        let all = try list(fileManager: fileManager)
        guard let snapshot = all.first(where: { $0.id == requested.id }) else {
            throw SnapshotError.notFound(requested.id.uuidString)
        }
        let encoder = VirtualMachineLibrary.makeEncoder()
        for var child in all where child.parentID == snapshot.id {
            child.parentID = snapshot.parentID
            try encoder.encode(child).write(
                to: directoryURL.appending(path: "\(child.id.uuidString)/snapshot.json"), options: .atomic
            )
        }
        try fileManager.removeItem(at: directoryURL.appending(
            path: snapshot.id.uuidString,
            directoryHint: .isDirectory
        ))
        if head(fileManager: fileManager) == snapshot.id {
            if let parent = snapshot.parentID {
                try writeHead(parent)
            } else {
                try? fileManager.removeItem(at: headURL)
            }
        }
    }

    private func writeHead(_ id: UUID) throws {
        try Data(id.uuidString.utf8).write(to: headURL, options: .atomic)
    }
}
