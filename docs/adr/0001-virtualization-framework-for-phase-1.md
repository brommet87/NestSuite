# 0001. Use Virtualization.framework for Linux and macOS guests

- Status: Accepted
- Date: 2026-11-08

## Context
NestSuite is built as an independent stack directly on Apple’s public frameworks, without embedding
another virtualization engine. On Apple silicon, third-party code cannot run at the
hypervisor exception level; every Mac virtualizer builds on Apple’s `Hypervisor.framework`
(low level, you write the VMM) or `Virtualization.framework` (high level, Apple provides VMM and devices).

macOS guests on Apple silicon are only possible through `Virtualization.framework`. Linux guests
work very well with it, including virtiofs, SPICE clipboard, Rosetta and save/restore.
Windows 11 on Arm is not supported by it in practice (no suitable display drivers).

## Decision
Phase 1 uses `Virtualization.framework` for Linux and macOS guests. All framework usage is confined
to the `NestVirtualization` module behind domain types from `NestCore`. Windows support will come
from NestSuite’s own VMM on `Hypervisor.framework`, added later as a second engine.

## Consequences
- Fast path to a usable, stable product for Linux and macOS guests.
- Some features depend on Apple’s pace (e.g. USB passthrough limited to mass storage, no 3D for Linux).
- The domain model must stay engine-agnostic so the second engine fits without UI changes.
- Development needs the `com.apple.security.virtualization` entitlement; ad-hoc signing is sufficient
  locally (verified on macOS 27 / M5 Pro, 2026-11-08).

## Alternatives considered
- **Own VMM first:** maximum control, but delays any usable result by many months and cannot run macOS guests.
- **Embedding an existing emulator/VMM:** faster to start, but adds a large foreign attack surface
  and ties the project to another engine’s design. Excluded in favor of an independent stack.
