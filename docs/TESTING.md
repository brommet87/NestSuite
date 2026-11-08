# Testing

## Strategy

| Layer | Framework | Runs in | What |
|---|---|---|---|
| `NestCore` unit tests | Swift Testing | `swift test`, CI | Validation, state machine, bundles, coding — exhaustive, parameterized |
| `NestVirtualization` tests | Swift Testing | `swift test`, CI | Host capability mapping; configuration building (0.2) |
| App tests | Swift Testing via `xcodebuild test` | CI | View models with fake library/workspace/engine |
| Integration tests | Swift Testing, tagged | locally / opt-in workflow | Boot a real Linux VM (needs entitlement and an image download) |
| Manual UI review | checklist | every UI PR | See [design/ACCESSIBILITY.md](design/ACCESSIBILITY.md) |

Rules:
- Domain logic is written so it can be tested without a hypervisor (inject `HostCapabilities`, file
  locations and side effects).
- Every bug fix comes with a test that fails without the fix.
- Tests never touch the user’s real library; they use temporary directories.
- Tests that need large downloads (Linux images, macOS IPSW) never run in the default suite. They are
  enabled with `NESTSUITE_INTEGRATION=1` (from 0.2).

## Running
```bash
make test-package   # seconds
make test           # package + app tests
```
