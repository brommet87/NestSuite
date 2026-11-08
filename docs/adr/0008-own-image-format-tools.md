# 0008. Own readers and writers for image formats

- Status: Accepted
- Date: 2026-11-08

## Context
Most distributions publish ARM64 cloud images as qcow2, while `Virtualization.framework` needs raw
disks. cloud-init’s NoCloud data source needs a small volume labelled `CIDATA`. Passwords for console
login must not be stored in plain text. The usual answers are external tools (a disk converter, `hdiutil`,
`mkpasswd`): they are foreign dependencies, some are not on a stock Mac, and none can run inside the
App Sandbox.

## Decision
NestSuite implements the three small, well-specified pieces itself, in `NestImages`:

- **`QCOW2Image`** — reads qcow2 v2/v3 (two-level cluster tables, deflate-compressed and zero clusters)
  and writes a sparse raw disk. Unsupported features (backing files, encryption, external data files,
  extended L2, zstd) are refused explicitly.
- **`FATImage`** — writes a FAT12 volume with VFAT long file names for the cloud-init seed.
- **`SHA512Crypt`** — the `$6$` password hash used by Linux `/etc/shadow`.

Each follows its published specification and is tested against it: hand-built qcow2 fixtures, a
read-back FAT parser plus macOS mounting the volume, and SHA-512-crypt reference vectors reproduced with
OpenSSL. Decompression uses Apple’s Compression framework; archives are unpacked with the system `tar`.

## Consequences
- Works in the sandboxed app and with a stock macOS; no extra install for users.
- About 600 lines of code we maintain, with full test coverage of the supported subset.
- New qcow2 features in future images could need extensions; they fail loudly, never silently.

## Alternatives considered
- **Bundling an external disk converter:** a large foreign dependency that conflicts with the
  independent-stack goal (ADR 0001).
- **Only raw-image distributions:** would drop Fedora, the RHEL family, openSUSE and Ubuntu.
- **`hdiutil` for the seed:** not available inside the App Sandbox.
