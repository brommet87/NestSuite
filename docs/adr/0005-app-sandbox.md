# 0005. Ship inside the App Sandbox

- Status: Accepted
- Date: 2026-11-08

## Context
A virtualization app handles untrusted guest operating systems and downloaded images. Limiting what
the host process itself can do reduces the impact of any bug.

## Decision
NestSuite runs in the App Sandbox with only these entitlements:
`virtualization`, `network.client`/`network.server` (NAT networking), `files.user-selected.read-write`
and `files.bookmarks.app-scope` (ISO/IPSW files and shared folders the user picks).

VM bundles live in the app container. Shared folders use security-scoped bookmarks stored in the
VM configuration.

## Consequences
- Users choose files and folders explicitly; the app cannot read arbitrary locations.
- Bridged networking (`com.apple.vm.networking`) needs a restricted entitlement from Apple and is out
  of scope until we have one.
- Importing VMs from arbitrary folders goes through an open panel.

## Alternatives considered
- **No sandbox:** simpler file handling, larger attack surface. Rejected.
