# Releasing

> Status: release automation is planned for 0.2. This document describes the intended process.

1. Update `CHANGELOG.md`: move *Unreleased* to a new version section.
2. Bump `MARKETING_VERSION` in `project.yml`.
3. Tag `vX.Y.Z` on `main`. The release workflow builds a universal Release build, signs it with the
   project’s Developer ID, notarizes it with Apple and attaches a `.dmg` and checksums to the GitHub release.

Secrets required in the repository (configured by a maintainer): Developer ID certificate (`.p12`)
and password, App Store Connect API key for notarization.

Until a Developer ID is configured, releases are source-only.

Distribution through the Mac App Store is not planned: it is incompatible with the GPL (ADR 0002).
