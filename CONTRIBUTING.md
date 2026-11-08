# Contributing to NestSuite

Thank you for helping! This guide explains how we work, so your contribution lands smoothly.

## Ground rules

- Be kind and constructive — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- Security problems go to [SECURITY.md](SECURITY.md), never to public issues.
- Code, comments, commit messages and documentation are written in **English**. The app itself is
  localized (currently English and German); translations are very welcome.

## Before you start

- **Bugs:** open an issue with the bug template. Include macOS version, Mac model and steps to reproduce.
- **Features:** open a feature request first. Larger changes need a short design discussion, and
  architectural changes need an ADR (see [docs/adr](docs/adr)).
- **Design:** UI changes follow the [design system](docs/design). Attach before/after screenshots
  in light and dark mode.

## Development setup

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Short version:

```bash
make bootstrap && make run
```

## Making a change

1. Create a branch from `main`: `feature/<short-name>`, `fix/<short-name>` or `docs/<short-name>`.
2. Keep pull requests focused: one logical change per PR.
3. Write tests. Domain logic belongs in `NestKit` and is unit-tested there (see [docs/TESTING.md](docs/TESTING.md)).
4. Run `make lint test` before pushing. CI runs the same checks.
5. Update `CHANGELOG.md` under *Unreleased* for user-visible changes.
6. New UI strings must be localized: add the German translation to the string catalog.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(library): show damaged bundles instead of hiding them
fix(core): round-trip creation dates exactly
docs(adr): record the concurrency model
```

## Code style

- Swift 6 language mode with complete strict concurrency. No `@unchecked Sendable` without a comment
  explaining why it is safe.
- SwiftFormat and SwiftLint configurations are authoritative (`make format`, `make lint`).
- No force unwraps outside tests (rare, justified exceptions are marked with a lint comment).
- Public API is documented with doc comments that explain *why*, not just *what*.
- Views use design tokens (`Tokens.*`), never literal colors or spacing values.

## Pull request review

Every PR needs one approving review and green CI. Reviewers check correctness, tests,
accessibility (VoiceOver, keyboard, contrast), localization and documentation.

## License of contributions

By contributing you agree that your contributions are licensed under the project’s
[GPL-3.0-or-later](LICENSE) license.
