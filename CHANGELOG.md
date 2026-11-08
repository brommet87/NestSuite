# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
