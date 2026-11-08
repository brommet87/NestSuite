# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added — 0.2 (Linux machines, in progress)
- Virtualization engine: EFI boot from ARM64 installer ISOs, sparse disk images, NAT networking with a
  stable MAC address, virtio graphics with display auto-resize, sound output, entropy, memory balloon,
  shared folders (virtiofs), shared clipboard (SPICE agent), Rosetta for x86-64 binaries.
- Exclusive per-machine lock so the app and `nestctl` never run the same machine twice.
- App: “New Virtual Machine” sheet with live validation, start/pause/resume/shut down/force shut down,
  machine display window, live status in the sidebar, quitting asks to shut down running machines.
- `nestctl create`, `nestctl run` (with `--iso` and `--console`), `nestctl logs`; exit code 75 for busy
  machines; clone, snapshot and rm refuse running machines.
- `make nestctl` builds a signed CLI; `Scripts/integration-boot-test.sh` boots a real installer image.

### Changed
- Machine sessions run on the main actor (ADR 0007, supersedes the queue detail of ADR 0003).

### Added
- App shell: library window with sidebar and detail view, Settings window, menu commands.
- VM library on disk: self-contained `.nestvm` bundles with atomic `config.json` writes,
  Finder-style sorting, unique naming and recovery UI for damaged bundles.
- Configuration model with host-aware validation (CPU, memory, disk, Rosetta, macOS guest support)
  and a VM lifecycle state machine.
- Design system: tokens, brand mark, empty state and status badge components.
- `Nestfile.yml`: declarative machine definitions with strict, line-numbered validation.
- `nestctl` command-line tool: `list`, `inspect`, `validate`, `clone`, `snapshot`, `rm`, `host`, with `--json` and sysexits exit codes.
- Linked clones and snapshots with branching, using APFS copy-on-write.
- English and German localization.
- App icon rendered from code; brand assets.
- Documentation: architecture, ADRs, design system, contributing, security policy.
- CI: lint, unit tests and app build on GitHub Actions.
