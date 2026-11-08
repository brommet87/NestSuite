# 0006. CLI-first design and declarative machine definitions

- Status: Accepted
- Date: 2026-11-08

## Context
Developers want reproducible environments that live in their repository, automation without
clicking, and disposable machines for tests and CI. A GUI-only tool can’t be scripted, reviewed or
reproduced across a team.

## Decision
- **Everything the app can do, the CLI can do.** `nestctl` is a first-class interface built on the
  same `NestKit` modules as the app. GUI features land together with their CLI command.
- **Stable machine-readable output.** Every command supports `--json`; JSON shapes are a public API
  (fields may be added, never renamed or removed without a major version). Errors in JSON mode are
  JSON too.
- **Documented exit codes** following `sysexits(3)`: 0, 1, 64, 65, 66, 73 (see [cli.md](../cli.md)).
- **`Nestfile.yml`** describes machines declaratively (YAML, versioned schema). The parser is strict:
  unknown keys are errors with a suggestion and a line number, so typos never fall back silently.
- **Copy-on-write first.** Clones and snapshots use APFS clones; on other volumes they still work
  as full copies and the CLI says so.
- **Two small, well-maintained dependencies**, both GPL-compatible: Yams (MIT, YAML parsing) and
  Swift Argument Parser (Apache-2.0). Neither is a virtualization engine (ADR 0001 is unaffected).

## Consequences
- Every new feature needs a CLI surface, JSON shape, tests and docs — slower, but complete.
- The JSON and exit-code contract must be versioned carefully.
- The CLI runs unsandboxed and reaches the app’s library inside its container; it must never
  touch a machine that is running (enforced by the daemon from 0.4).

## Alternatives considered
- **TOML or JSON for the Nestfile:** TOML is less common for this kind of file; JSON is unfriendly to edit by hand.
- **Hand-written argument parsing:** no dependency, but worse help, completion and validation.
