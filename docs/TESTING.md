# Testing

## Strategy

| Layer | Framework | Runs in | What |
|---|---|---|---|
| `NestCore` unit tests | Swift Testing | `swift test`, CI | Validation, state machine, bundles, coding — exhaustive, parameterized |
| `NestVirtualization` tests | Swift Testing | `swift test`, CI | Host capability mapping; configuration building (0.2) |
| App tests | Swift Testing via `xcodebuild test` | CI | View models with fake library/workspace/engine |
| Engine tests | Swift Testing | `swift test`, CI | Device configuration, sparse disks, identity files, locking — no entitlement needed |
| Image tests | Swift Testing | `swift test`, CI | Catalog integrity, source resolution against a stub server, qcow2 against hand-built fixtures, FAT seed read back, SHA-512-crypt reference vectors |
| End-to-end (manual) | `nestctl up` with a Nestfile | locally | Real download, provisioning and in-guest checks; see [images.md](images.md#verified-end-to-end) |
| Integration test | `Scripts/integration-boot-test.sh <iso>` | locally | Boots a real ARM64 installer with a signed `nestctl`, checks it stays up, refuses a second start and stops cleanly |
| Manual UI review | checklist | every UI PR | See [design/ACCESSIBILITY.md](design/ACCESSIBILITY.md) |

Rules:
- Domain logic is written so it can be tested without a hypervisor (inject `HostCapabilities`, file
  locations and side effects).
- Every bug fix comes with a test that fails without the fix.
- Tests never touch the user’s real library; they use temporary directories.
- Tests that need an entitlement or large downloads (Linux images, macOS IPSW) never run in the
  default suite; use the integration script.
- Debug builds accept `-NestSuiteAutostart <name>` and `-NestSuiteInstaller <path>` to start a machine
  and open its window without clicking, for UI checks and documentation screenshots. Release builds
  don’t contain this code.

## Running
```bash
make test-package   # seconds
make test           # package + app tests
```
