# Images

NestSuite creates Linux machines from official distribution images. List them with
`nestctl images`; in the app they appear under **New Virtual Machine → Ready-Made System / Installer**.

## Two kinds

| Kind | What you get | Use it with |
|---|---|---|
| **cloud** | A ready system that boots in about a minute and is set up on first boot by cloud-init: your user (SSH keys from `~/.ssh/*.pub` with `nestctl`, a password in the app), shared folders mounted under `/mnt/<tag>`, Rosetta registered | `image:` in a Nestfile, the app’s “Ready-Made System” |
| **installer** | The distribution’s official ARM64 installer ISO; you install interactively | `nestctl run <machine> --iso <image>`, the app’s “Installer” |

Cloud images: Ubuntu 26.04 / 24.04, Debian 13 / 12, Fedora 44, AlmaLinux 10 / 9, Rocky Linux 10 / 9,
CentOS Stream 10 / 9, openSUSE Tumbleweed, Alpine Linux 3.24, Kali Linux.
Installers: the same families plus NixOS, Gentoo and Grml (rescue system).

## Trust and verification

- Every entry points to the distribution’s **own HTTPS server** — no mirrors run by NestSuite.
- The current file name is read from the distribution’s **published checksum list** or folder index at
  download time, so point releases are picked up automatically.
- Every download is checked against that **SHA-256 or SHA-512** checksum before use. A mismatch aborts
  the download (`the download is corrupt or was tampered with`).
- Prepared disks must contain a **partition table**; bare file-system images are rejected instead of
  producing a machine that cannot boot.

## Formats

| Published as | What NestSuite does |
|---|---|
| `.tar.gz` / `.tar.xz` with a raw disk | unpacks with the system `tar` |
| qcow2 (copy-on-write disk format) | converts to a sparse raw disk with NestSuite’s own reader ([ADR 0008](adr/0008-own-image-format-tools.md)) |
| ISO | used as is |

## Storage

Prepared images are cached once per release and shared by all machines:

```
~/Library/Containers/io.github.brommet87.NestSuite/Data/Library/Application Support/NestSuite/Images/
└── ubuntu-24.04/<checksum>.raw
```

A machine’s disk is an **APFS clone** of the cached image, grown to the machine’s disk size — it takes
no extra space until the guest writes. The guest grows its file system on first boot.

## What first boot sets up (cloud images)

| Item | Detail |
|---|---|
| User | your macOS short name (sanitized), `sudo` without password |
| Login | SSH keys (`nestctl`) or a password stored only as a SHA-512-crypt hash (app) |
| Shared folders | `mount -t virtiofs <tag> /mnt/<tag>`, persistent in `/etc/fstab` |
| Rosetta | mounted at `/media/rosetta`, registered via `/etc/binfmt.d`; on SELinux systems the mount gets the `bin_t` context so SELinux can stay enforcing |
| Readiness | the guest prints `NESTSUITE-READY share:<tag>=ok rosetta=ok` to its console; `nestctl up` shows it and runs `postProvision` hooks |

A project’s own `cloud-init.yaml` (`provision.cloudInit` in the Nestfile) is added as a second part and
merged by cloud-init.

## Verified end to end

On a Mac with Apple silicon (macOS 27): Debian 13, Ubuntu 24.04 and AlmaLinux 10 were created with
`nestctl up`, provisioned by cloud-init, and checked inside the guest — shared folder in both
directions, file system grown, an x86-64 binary running through Rosetta (AlmaLinux with SELinux
enforcing, also after a reboot), and password login in the app window (Ubuntu). The other entries are
verified to resolve and match their published checksums; reports from other distributions are welcome.

## Known limitations

- Debian’s cloud kernel has no virtio graphics driver: the machine window stays dark after boot.
  Use SSH or the console log, or an Ubuntu/Fedora image when you want the window. A built-in console
  view is planned.
- Images with only qcow2 features NestSuite does not support (backing files, encryption, zstd) are
  rejected with a clear error.
