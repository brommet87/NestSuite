# Roadmap

NestSuite is built in phases. Each phase ships something usable and fully tested before the next one
starts. Dates are intentionally absent: this is a volunteer-driven open-source project.

**Product pillars**

1. **Developer workflow first.** Declarative `Nestfile`, a scriptable CLI with JSON output, instant
   clones and snapshots, headless operation for CI.
2. **Real isolation.** Every machine is its own virtual machine — no shared kernel between machines.
3. **Feels like the Mac.** Native SwiftUI app, menu bar, Finder and notifications integration.
4. **Open by default.** Open guest tools, a documented host–guest protocol, no telemetry, works offline.

## 0.1 — Foundation
- [x] Project structure, CI, linting, documentation, design system
- [x] VM library with `.nestvm` bundles and damaged-bundle recovery
- [x] Configuration model, validation, lifecycle state machine
- [x] `Nestfile.yml`: declarative machine definitions with precise, line-numbered errors
- [x] `nestctl`: `list`, `inspect`, `validate`, `clone`, `snapshot`, `rm`, `host` — JSON output, documented exit codes
- [x] Linked clones (APFS copy-on-write, `--count` for disposable fleets)
- [x] Snapshots with branching (APFS copy-on-write)
- [x] English and German UI

## 0.2 — Linux machines *(in progress)*
- [x] Virtualization engine on `Virtualization.framework` (main-actor sessions, ADR 0007)
- [x] EFI boot from any ARM64 installer ISO, sparse disk images, NAT networking with stable MAC
- [x] Exclusive per-machine lock: the app and `nestctl` never run the same machine twice
- [x] `nestctl create`, `run` (with optional serial console), `logs`
- [x] App: create machines, start/pause/resume/shut down, display window with auto-resize, safe quit
- [x] Devices wired: shared folders (virtiofs), shared clipboard (SPICE), Rosetta, sound output (virtio-snd)
- [ ] Verified guest-side setup guides for shared folders, clipboard and Rosetta (Ubuntu, Fedora, Debian)
- [ ] Image catalog with checksums (`image: ubuntu-24.04`, `distro:version`)
- [ ] Fast boot path (direct kernel boot)
- [ ] `nestctl up` / `down` driven by the Nestfile
- [ ] cloud-init provisioning (NoCloud seed), hooks (`preStart`, `postProvision`, …)

## 0.3 — macOS machines and isolation
- [ ] macOS guests: restore-image download with progress and resume, installation flow
- [ ] Two-instance limit surfaced clearly
- [ ] Isolated machines (`isolated: true`): no shares, no clipboard, no agent forwarding, optional no network —
      a safe sandbox for untrusted code and autonomous coding agents

## 0.4 — Headless and automation
- [ ] `nestd` background daemon; GUI and CLI share all state and settings
- [ ] Local HTTP API (Unix socket) for programmatic control
- [ ] SSH into any machine (`ssh dev.nest`), key-only, SSH agent forwarding; works with VS Code Remote-SSH and Ansible
- [ ] `nestctl top`, `nestctl logs`, `nestctl config`
- [ ] Menu bar app: start/stop, open terminal, open in Finder, copy addresses
- [ ] Suspend/resume (save state)

## 0.5 — Guest agent
- [ ] Open guest agent as regular distro packages (apt, dnf, apk) with a public protocol specification
- [ ] File-change events from Mac to guest, so hot-reload in the guest reacts to edits on the Mac
- [ ] Run Mac commands and send notifications from the guest
- [ ] MCP server: coding agents create, use and discard isolated machines on their own
- [ ] Drag & drop, guest notifications as Mac notifications

## 0.6 — Networking and files
- [ ] Zero-config names: every machine reachable as `name.nest.local`, with automatic HTTPS via a local CA in the Keychain
- [ ] Automatic port forwarding (Nestfile `ports`, runtime changes without restart)
- [ ] `host.nest.internal` to reach Mac services from guests
- [ ] Guest files in Finder; machine-to-machine file access
- [ ] Memory ballooning (unused RAM goes back to macOS), disks that shrink when the guest frees space
- [ ] Idle CPU and boot-time benchmarks in CI

## 0.7 — Images and sharing
- [ ] Push/pull machine images to/from any OCI registry (layered, content-addressed)
- [ ] Snapshot diff: which files and packages changed between two snapshots
- [ ] Proxy and VPN-friendly DNS configuration

## 0.8 — Containers
- [ ] Container engine in a managed Linux machine, Docker-compatible socket and CLI context
- [ ] Container and volume files in Finder

## 0.9 — Kubernetes
- [ ] Single-node cluster in a managed machine, local images usable without a registry

## Later
- [ ] Seamless windows: guest apps as Mac windows, in the Dock and Spotlight, file-type associations
- [ ] Own VMM on `Hypervisor.framework` (Rust), then Windows 11 on Arm (community-supported, no vendor certification)
- [ ] USB passthrough beyond mass storage (requires the own VMM)
- [ ] Team mode: run machines on a shared Mac and use them over the network
- [ ] Secrets injection from the Keychain at runtime, never written to disk
- [ ] Battery mode: pause or throttle machines on battery power
- [ ] Per-project activation when entering a folder with a Nestfile
- [ ] Audit log: which machine accessed which host folders, when
- [ ] Management: policies, golden images, MDM integration; encrypted machines
- [ ] Live migration between Macs

Want to help with a phase? See [CONTRIBUTING.md](CONTRIBUTING.md) and the issue tracker.
