# Development

## Prerequisites
- macOS 15 or later, Apple silicon recommended
- Xcode 16 or later (CI uses the latest stable Xcode)
- [Homebrew](https://brew.sh)

## First run
```bash
make bootstrap   # XcodeGen, SwiftLint, SwiftFormat
make generate    # creates NestSuite.xcodeproj from project.yml
open NestSuite.xcodeproj
```
or simply `make run`.

## Everyday tasks
| Task | Command |
|---|---|
| Build | `make build` |
| Run | `make run` |
| All tests | `make test` |
| Fast domain tests only | `make test-package` |
| Lint | `make lint` |
| Format | `make format` |
| Re-render app icon | `make icon` |

## Signing
Debug builds are ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`) with the entitlements in
`App/NestSuite.entitlements`. `Virtualization.framework` accepts ad-hoc signatures for local
development; no Apple Developer account is required. Release signing: [RELEASING.md](RELEASING.md).

## Project layout
```
App/                 app target (views, view models, resources, tests)
Packages/NestKit/    domain, virtualization adapter, design system (+ tests)
Design/Brand/        logo and app icon sources
Scripts/             tooling (icon rendering)
docs/                architecture, ADRs, design system, references
project.yml          XcodeGen spec (source of truth for the Xcode project)
```

## Where VMs are stored
`~/Library/Containers/io.github.brommet87.NestSuite/Data/Library/Application Support/NestSuite/Machines`
(“Open Library Folder” on the welcome screen opens it).

## Localization
UI strings live in `App/Resources/Localizable.xcstrings` (app) and
`Packages/NestKit/Sources/NestDesign/Resources/Localizable.xcstrings` (components). After adding
strings, run `xcodebuild -exportLocalizations -project NestSuite.xcodeproj -localizationPath build/loc -exportLanguage de`
to sync the catalog, then add the German translation (see the glossary in
[design/VOICE-AND-TONE.md](design/VOICE-AND-TONE.md)).
