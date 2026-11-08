# 0004. XcodeGen and a local Swift package

- Status: Accepted
- Date: 2026-11-08

## Context
`.xcodeproj` files are hard to review and cause merge conflicts. A signed `.app` with entitlements,
asset catalogs and string catalogs can’t be produced by Swift Package Manager alone.

## Decision
- The Xcode project is generated from `project.yml` with XcodeGen. The generated project is not committed.
- All non-UI code lives in the local package `Packages/NestKit` (`NestCore`, `NestVirtualization`,
  `NestDesign`), testable with `swift test` in seconds.
- The app target is a thin shell: views, view models, resources.

## Consequences
- Contributors need XcodeGen (`make bootstrap`). `make` targets hide the details.
- Clean diffs and no project-file conflicts.
- Clear module boundaries enforce the dependency rule from the architecture document.

## Alternatives considered
- **Committed .xcodeproj:** zero tooling, but conflict-prone and unreviewable.
- **Tuist:** more powerful, but heavier than needed for one app target.
