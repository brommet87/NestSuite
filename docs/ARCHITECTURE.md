# Architecture

This document explains how NestSuite is put together and why. Decisions with lasting consequences
are recorded as [ADRs](adr/).

## Goals

1. **Safe by default.** Guests are isolated; anything that crosses the boundary (folders, clipboard)
   is explicit and per-VM.
2. **Testable.** Business logic runs in plain unit tests without a hypervisor, an app bundle or a
   network connection.
3. **Replaceable engine.** Phase 1 uses `Virtualization.framework`. A later phase adds NestSuite’s own
   VMM on `Hypervisor.framework` for Windows guests. The UI and domain model must not care which one
   runs a machine.

## Module overview

```
┌──────────────────────────────── NestSuite.app ────────────────────────────────┐
│  App/Sources            SwiftUI views, view models (@MainActor), commands       │
│        │                                                                        │
│        ▼                                                                        │
│  ┌──────────── NestKit (Swift package, Packages/NestKit) ─────────────────┐    │
│  │  NestCLI / nestctl   command-line interface (JSON output, exit codes)   │    │
│  │  NestDesign          tokens, components (EmptyState, StatusBadge, …)    │    │
│  │  NestVirtualization  adapter to Virtualization.framework                │    │
│  │  NestImages          catalog, verified downloads, qcow2, cloud-init     │    │
│  │  NestSpec            Nestfile.yml parsing and validation                │    │
│  │  NestCore            domain model — no Apple virtualization APIs, no UI │    │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

Dependency rule: arrows point inward only. `NestCore` depends on Foundation alone. `NestSpec`,
`NestVirtualization` and `NestDesign` depend on `NestCore`. `NestCLI` and the app sit on top.
The app and `nestctl` are two front ends over the same modules (ADR 0006).

### NestCore

| Type | Responsibility |
|---|---|
| `VirtualMachineConfiguration` | Everything that describes a VM. Codable value type, persisted as `config.json`. |
| `HostCapabilities` | What the Mac can offer. Filled in by `NestVirtualization`, faked in tests. |
| `ConfigurationValidator` | Turns a configuration + host into structured `ConfigurationIssue`s (errors and warnings). |
| `VirtualMachineState` / `VirtualMachineEvent` | Lifecycle state machine. All transitions go through `applying(_:)`. |
| `VirtualMachineBundle` / `VirtualMachineLibrary` | On-disk `.nestvm` bundles: create, list, load, clone (APFS copy-on-write), trash. |
| `SnapshotStore` | Snapshot tree inside a bundle (`Snapshots/`), restore and delete with re-parenting. |

### NestImages

| Type | Responsibility |
|---|---|
| `ImageCatalog` / `CatalogImage` | Official cloud images and installers; how to find the current file on the distribution’s server |
| `SourceResolver` | Resolves file name and checksum from checksum lists, folder indexes and pointer files |
| `ImageStore` | Downloads, verifies (SHA-256/512), unpacks or converts, checks for a partition table, caches per release |
| `QCOW2Image`, `FATImage`, `SHA512Crypt` | Own format tools (ADR 0008) |
| `CloudInitSeed` | First-boot configuration and the `CIDATA` volume |
| `MachineProvisioner` | Bundle + APFS-cloned disk + seed in one step; reads the guest’s readiness report |

### NestSpec

Parses `Nestfile.yml` into `MachineSpec`s with strict key checking, line numbers and typo
suggestions, and validates them against the host and file system (`NestfileValidator`). `auto`
resources resolve through the same recommendation logic the app uses. Reference: [nestfile.md](nestfile.md).

### NestCLI

`nestctl` commands built on Swift Argument Parser. Dependencies (output sink, host, working
directory) are injected, so every command is tested end to end against a temporary library.
Reference: [cli.md](cli.md).

Domain types never contain user-facing strings. The app maps issues, errors and states to localized,
actionable text (`App/Sources/Library/Presentation.swift`). This keeps wording in one place and lets
the same issue appear inline next to a field or in a list.

### NestVirtualization

The only module that imports `Virtualization`.

| Type | Responsibility |
|---|---|
| `MachinePreparation` | Creates per-machine files once: sparse disk image, EFI variable store, machine identifier, MAC address |
| `ConfigurationBuilder` | Translates a `VirtualMachineConfiguration` into a `VZVirtualMachineConfiguration` — all virtio, nothing emulated |
| `VirtualMachineSession` | Owns one `VZVirtualMachine` on the main actor (ADR 0007), drives the state machine, holds the `BundleLock` while running |
| `HostCapabilities.current()` | Framework limits and Rosetta availability |

The session always calls `validate()` before creating a `VZVirtualMachine` (an invalid configuration
raises an Objective-C exception in the initializer) and translates framework callbacks into
`VirtualMachineEvent`s.

Virtual hardware of a Linux machine: EFI boot loader, virtio block disk, optional read-only USB
installer drive, virtio network (NAT, stable MAC), virtio graphics, USB keyboard and pointer, virtio
sound (output only — microphone will be opt-in), entropy, memory balloon, SPICE agent port for the
clipboard, virtiofs shares and Rosetta, serial console to `Console.log`.

### NestDesign

Design tokens and reusable components, documented in [docs/design](design/). Views in the app use
tokens only, never literal values.

## On-disk format

```
~/Library/Containers/io.github.brommet87.NestSuite/Data/Library/Application Support/NestSuite/Machines/
└── Ubuntu.nestvm/
    ├── config.json          schemaVersion, hardware, integration settings
    ├── Disk.img             sparse raw image (0.2)
    ├── MachineIdentifier    (0.2)
    ├── NVRAM                EFI variables, Linux (0.2)
    ├── AuxiliaryStorage     macOS boot data (0.3)
    ├── HardwareModel        macOS (0.3)
    ├── SavedState.vzvmsave  only while suspended (0.4)
    └── Snapshots/           HEAD + one folder per snapshot (APFS clones of the state files)
```

- `config.json` is written atomically and carries a `schemaVersion`. Newer files are rejected with a
  clear message instead of being misread.
- A bundle that can’t be read is listed as *damaged* rather than hidden, with “Show in Finder” and
  “Move to Trash”.
- Deleting moves bundles to the Trash, so it can be undone.

## Concurrency

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`.
- View models are `@MainActor @Observable`.
- File I/O runs in detached tasks; `VirtualMachineLibrary` is a `Sendable` value type.
- Each running VM will be owned by its own actor wrapping a `VZVirtualMachine` and its dispatch queue
  (0.2, [ADR 0003](adr/0003-swift6-concurrency-model.md)).

## Security

App Sandbox, minimal entitlements, security-scoped bookmarks for shared folders.
See [SECURITY.md](../SECURITY.md) and [ADR 0005](adr/0005-app-sandbox.md).

## Testing

See [TESTING.md](TESTING.md). In short: `NestCore` is tested exhaustively with Swift Testing; the app
target tests view models with fakes; real VM boots are integration tests, kept out of the default run.
