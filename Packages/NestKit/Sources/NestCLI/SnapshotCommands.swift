// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Foundation
import NestCore

/// `nestctl snapshot …` — point-in-time copies with branching, backed by APFS clones.
struct SnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Take, list, restore and delete snapshots (instant on APFS).",
        discussion: """
        Snapshots form a tree: restore an older snapshot, change things and take a new one to start \
        a branch. The machine must be stopped.
        """,
        subcommands: [Create.self, ListSnapshots.self, Restore.self, Delete.self],
        aliases: ["snap"]
    )

    struct SnapshotDTO: Encodable, Equatable {
        let id: UUID
        let name: String
        let note: String?
        let createdAt: Date
        let parentID: UUID?
        let isHead: Bool
    }

    /// Resolves the machine and its snapshot store, or fails with exit code 66.
    static func store(
        for machine: String, options: GlobalOptions, renderer: Renderer, requireStopped: Bool = true
    ) throws -> SnapshotStore {
        guard let entry = try options.resolvedLibrary().entry(named: machine) else {
            throw renderer.fail("no machine named “\(machine)” (see `nestctl list`)", code: NestExitCode.notFound)
        }
        guard case .machine = entry else {
            throw renderer.fail("“\(machine)” is damaged", code: NestExitCode.invalidInput)
        }
        if requireStopped {
            try renderer.ensureNotRunning(entry.id, name: machine)
        }
        return SnapshotStore(bundle: VirtualMachineBundle(url: entry.id))
    }

    static func find(_ reference: String, in store: SnapshotStore, renderer: Renderer) throws -> Snapshot {
        do {
            return try store.find(reference)
        } catch {
            throw renderer.fail("no snapshot “\(reference)” (see `nestctl snapshot list`)", code: NestExitCode.notFound)
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Take a snapshot of a stopped machine.")

        @OptionGroup var options: GlobalOptions
        @Argument(help: "Machine name.") var machine: String
        @Argument(help: "Snapshot name, e.g. “clean-install”.") var name: String
        @Option(help: "A note describing the snapshot.") var note: String?

        func run() throws {
            let renderer = Renderer(json: options.json, sink: Environment.current.sink)
            let store = try SnapshotCommand.store(for: machine, options: options, renderer: renderer)
            if !store.supportsCopyOnWrite(), !options.json {
                Environment.current.sink
                    .writeError("note: this volume has no copy-on-write; the snapshot is a full copy")
            }
            let snapshot: Snapshot
            do {
                snapshot = try store.create(name: name, note: note)
            } catch SnapshotError.nameAlreadyUsed {
                throw renderer.fail("a snapshot named “\(name)” already exists", code: NestExitCode.cannotCreate)
            } catch SnapshotError.emptyName {
                throw renderer.fail("the snapshot name is empty", code: NestExitCode.usage)
            }
            let dto = SnapshotDTO(
                id: snapshot.id, name: snapshot.name, note: snapshot.note,
                createdAt: snapshot.createdAt, parentID: snapshot.parentID, isHead: true
            )
            try renderer
                .emit(dto) {
                    "✔ snapshot “\(snapshot.name)” (\(snapshot.id.uuidString.prefix(8).lowercased())) of \(machine)"
                }
        }
    }

    struct ListSnapshots: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Show the snapshot tree.",
            aliases: ["ls"]
        )

        @OptionGroup var options: GlobalOptions
        @Argument(help: "Machine name.") var machine: String

        func run() throws {
            let renderer = Renderer(json: options.json, sink: Environment.current.sink)
            // Listing is read-only, so it works while the machine runs.
            let store = try SnapshotCommand.store(
                for: machine,
                options: options,
                renderer: renderer,
                requireStopped: false
            )
            let snapshots = try store.list()
            let head = store.head()
            let dtos = snapshots.map {
                SnapshotDTO(
                    id: $0.id,
                    name: $0.name,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    parentID: $0.parentID,
                    isHead: $0.id == head
                )
            }
            try renderer.emit(dtos) {
                snapshots.isEmpty
                    ? "No snapshots. Take one with `nestctl snapshot create \(machine) <name>`."
                    : snapshotTree(snapshots, head: head)
            }
        }
    }

    struct Restore: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Restore a snapshot. Changes since then are discarded.",
            discussion: "Requires --yes, because unsaved changes to the machine are lost."
        )

        @OptionGroup var options: GlobalOptions
        @Argument(help: "Machine name.") var machine: String
        @Argument(help: "Snapshot name or id prefix.") var snapshot: String
        @Flag(name: .shortAndLong, help: "Confirm that changes since the snapshot may be discarded.") var yes = false

        func run() throws {
            let renderer = Renderer(json: options.json, sink: Environment.current.sink)
            guard yes else {
                throw renderer.fail(
                    "restoring discards all changes since “\(snapshot)”; run again with --yes to confirm",
                    code: NestExitCode.usage
                )
            }
            let store = try SnapshotCommand.store(for: machine, options: options, renderer: renderer)
            let target = try SnapshotCommand.find(snapshot, in: store, renderer: renderer)
            try store.restore(target)
            try renderer
                .emit(["restored": target.name, "machine": machine]) { "✔ \(machine) restored to “\(target.name)”" }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm",
            abstract: "Delete a snapshot (the tree stays connected)."
        )

        @OptionGroup var options: GlobalOptions
        @Argument(help: "Machine name.") var machine: String
        @Argument(help: "Snapshot name or id prefix.") var snapshot: String

        func run() throws {
            let renderer = Renderer(json: options.json, sink: Environment.current.sink)
            let store = try SnapshotCommand.store(for: machine, options: options, renderer: renderer)
            let target = try SnapshotCommand.find(snapshot, in: store, renderer: renderer)
            try store.delete(target)
            try renderer.emit(["deleted": target.name, "machine": machine]) { "✔ deleted snapshot “\(target.name)”" }
        }
    }
}

/// Renders snapshots as a tree, marking the one the current state descends from:
///
/// ```
/// ○ base          2026-11-08 18:00  a1b2c3d4
/// ├─○ feature-a   2026-11-08 18:10  e5f6a7b8
/// └─● feature-b   2026-11-08 18:20  c9d0e1f2   ← current
/// ```
func snapshotTree(_ snapshots: [Snapshot], head: UUID?) -> String {
    let ids = Set(snapshots.map(\.id))
    let children = Dictionary(grouping: snapshots) { $0.parentID.flatMap { ids.contains($0) ? $0 : nil } }
    let format = Date.FormatStyle(date: .numeric, time: .shortened)
    var lines: [String] = []

    func visit(_ snapshot: Snapshot, prefix: String, connector: String) {
        let marker = snapshot.id == head ? "●" : "○"
        let suffix = snapshot.id == head ? "   ← current" : ""
        let short = snapshot.id.uuidString.prefix(8).lowercased()
        let date = snapshot.createdAt.formatted(format)
        lines.append("\(prefix)\(connector)\(marker) \(snapshot.name)  \(date)  \(short)\(suffix)")
        let kids = children[snapshot.id] ?? []
        let childPrefix = prefix + (connector == "├─" ? "│ " : connector.isEmpty ? "" : "  ")
        for (index, child) in kids.enumerated() {
            visit(child, prefix: childPrefix, connector: index == kids.count - 1 ? "└─" : "├─")
        }
    }

    for root in children[nil] ?? [] {
        visit(root, prefix: "", connector: "")
    }
    return lines.joined(separator: "\n")
}
