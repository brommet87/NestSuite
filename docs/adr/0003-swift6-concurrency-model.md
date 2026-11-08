# 0003. Swift 6 strict concurrency and actor-owned VMs

- Status: Accepted
- Date: 2026-11-08

## Context
`VZVirtualMachine` is bound to the dispatch queue it was created on; all calls and delegate callbacks
happen there, and its types are not `Sendable`. Retrofitting an isolation model after the UI exists is
expensive and error-prone.

## Decision
- The whole project compiles in Swift 6 language mode with complete strict concurrency.
- UI state lives in `@MainActor @Observable` view models.
- Each running VM is owned by one actor (`VirtualMachineSession`, 0.2) that creates the
  `VZVirtualMachine` on a private serial queue and is the only code touching it. The actor exposes
  intents (`start`, `pause`, …) and publishes `VirtualMachineState` changes via `AsyncStream`.
- State changes always go through `VirtualMachineState.applying(_:)`; rejected transitions are
  programming errors and are logged.
- The engine is used through a protocol so view models are tested with a fake engine.

## Consequences
- Data races are compile-time errors.
- Small amount of boilerplate to hop between the VM queue and the actor.
- The VM display view (`VZVirtualMachineView`) needs main-thread access to the machine; the session
  hands it over in a controlled way.

## Alternatives considered
- **Everything on the main actor:** simplest, but blocks the UI during slow framework calls (save/restore).
- **Swift 5 mode with warnings:** postpones the problem.
