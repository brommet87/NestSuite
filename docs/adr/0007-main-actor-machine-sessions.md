# 0007. Machine sessions run on the main actor

- Status: Accepted (supersedes the queue detail of ADR 0003)
- Date: 2026-11-08

## Context
ADR 0003 planned one actor per running machine, owning a `VZVirtualMachine` on a private serial
queue. While implementing the engine we confirmed from the framework headers that a machine created
without a queue operates on the main queue, and that `VZVirtualMachineView` — the display — needs the
machine on the main thread. A private queue would require constant hops between that queue, an actor
and the main thread, each one a chance for data races around non-`Sendable` framework types.

## Decision
- `VirtualMachineSession` is a `@MainActor @Observable` class that owns the `VZVirtualMachine`
  (created on the main queue) and is the only code touching it.
- The framework delegate is a `@MainActor` class conforming with `@preconcurrency`, so the runtime
  verifies that callbacks arrive on the main actor.
- Every state change still goes through `VirtualMachineState.applying(_:)`.
- An exclusive `flock(2)` lock on the bundle (`BundleLock`) is held while a machine runs, so the app
  and `nestctl` can never run the same machine twice.

## Consequences
- Compile-time data-race safety with very little code; SwiftUI observes sessions directly.
- The main thread only handles control calls (start, stop, pause). The guest’s CPUs, devices and I/O
  run on the framework’s own threads, so UI responsiveness is unaffected.
- Long-running framework calls are `async` and do not block the main actor.
- If profiling ever shows main-thread contention, a session can move to a dedicated queue behind the
  same interface.

## Alternatives considered
- **Actor + private queue (ADR 0003):** more isolation on paper, but more hops and bridging code for
  no measurable benefit, and the display still needs the main thread.
