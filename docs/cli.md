# `nestctl` reference

`nestctl` controls NestSuite from the terminal and from scripts. Every command accepts `--json`
and `--library <path>`.

```bash
swift build --package-path Packages/NestKit --product nestctl -c release
cp "$(swift build --package-path Packages/NestKit -c release --show-bin-path)/nestctl" /usr/local/bin/
```

## Commands

| Command | What it does |
|---|---|
| `nestctl list` (`ls`) | List machines (damaged ones included, with the reason) |
| `nestctl inspect <name>` | Show a machine’s configuration |
| `nestctl validate [path] [--strict]` | Check a Nestfile against this Mac (`--strict`: warnings fail too) |
| `nestctl clone <source> <name> [--count N]` | Linked clones; with `--count`: `name-1 … name-N` |
| `nestctl snapshot create <machine> <name> [--note]` | Take a snapshot |
| `nestctl snapshot list <machine>` | Show the snapshot tree (● marks the current branch) |
| `nestctl snapshot restore <machine> <snapshot> --yes` | Restore; changes since then are discarded |
| `nestctl snapshot rm <machine> <snapshot>` | Delete a snapshot; children are re-attached |
| `nestctl rm <names…> [--force]` | Move to Trash, or delete permanently with `--force` |
| `nestctl host` | CPU, memory and feature limits of this Mac |

Machines are found by name, case-insensitively. Snapshots by name or a unique id prefix (≥ 4 characters).

## Library location
1. `--library <path>`
2. `$NESTSUITE_LIBRARY`
3. the NestSuite app’s library (`~/Library/Containers/io.github.brommet87.NestSuite/Data/Library/Application Support/NestSuite/Machines`)

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Unexpected error |
| 64 | Usage error (wrong arguments, missing `--yes`) |
| 65 | Invalid input (Nestfile errors, damaged machine) |
| 66 | Not found (machine, snapshot or Nestfile) |
| 73 | Cannot create (name already exists, copy failed) |

## JSON output
- Sizes are always in bytes (`memoryBytes`, `diskBytes`).
- Errors in JSON mode are printed to stdout as `{"error": "…", "exitCode": 66}`.
- Fields may be added in minor versions; they are never renamed or removed without a major version.

## Examples

```bash
# 20 disposable test machines from a prepared base, removed afterwards
nestctl clone ubuntu-base ci --count 20
nestctl rm --force $(nestctl list --json | jq -r '.[] | select(.name | startswith("ci-")) | .name')

# Gate CI on a valid Nestfile
nestctl validate --strict --json > nestfile-report.json

# Try something risky, roll back
nestctl snapshot create dev before-upgrade
nestctl snapshot restore dev before-upgrade --yes
```
