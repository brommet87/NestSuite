# 0002. License the project under GPL-3.0-or-later

- Status: Accepted
- Date: 2026-11-08

## Context
NestSuite is meant as an open, exemplary project. The license decides whether improvements must stay open.

## Decision
GPL-3.0-or-later for all source code. Source files carry an SPDX header.

## Consequences
- Derivatives and redistributed versions must remain open source.
- Distribution through the Mac App Store is incompatible with GPL terms; releases are distributed as
  notarized downloads from GitHub.
- Third-party dependencies must be GPL-3.0-compatible (MIT, BSD, Apache-2.0 are fine).

## Alternatives considered
- **Apache-2.0:** more permissive with patent grant, but allows closed forks.
- **MIT:** simplest, no patent clause, allows closed forks.
