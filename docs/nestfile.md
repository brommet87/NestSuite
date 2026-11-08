# `Nestfile.yml` reference

A Nestfile describes one or more machines for a project. Commit it next to your code; teammates get
the same environment. File names searched: `Nestfile.yml`, `Nestfile.yaml`, `Nestfile`.

```yaml
version: 1
machines:
  dev:
    guest: linux              # linux | macOS            (required)
    image: ubuntu-24.04       # catalog cloud image (`nestctl images`)
    cpus: 4                   # number | auto            (default: auto)
    memory: 8GiB              # size | auto              (default: auto)
    disk: 40GiB               # size | auto              (default: auto)
    rosetta: true             # x86-64 binaries in Linux (default: on when available)
    clipboard: true           # shared clipboard         (default: true)
    network: nat              # nat | none               (default: nat)
    shares:
      - host: .               # relative to this file; ~ is expanded
        tag: workspace        # guest: mount -t virtiofs workspace /workspace
        readOnly: false
    ports:
      - 3000                  # host 3000 → guest 3000
      - "8080:80"             # host 8080 → guest 80
      - "5353:53/udp"
      - { host: 9000, guest: 9001, protocol: tcp }
    provision:
      cloudInit: ./cloud-init.yaml
    hooks:                    # executable scripts run on the Mac
      preStart: ./scripts/pre-start.sh
      postStart: ./scripts/post-start.sh
      postProvision: ./scripts/seed-db.sh
      preStop: ./scripts/pre-stop.sh
```

## Rules
- **Strict keys:** unknown keys are errors, with a suggestion for likely typos (`memroy` → `memory`).
- **Sizes** use binary units: `512MiB`, `8GiB`, `1TiB`, or the shorthands `M`, `G`, `T`.
  `GB`/`MB` are rejected as ambiguous.
- **`auto`** picks values for the Mac running the machine (half the cores, a quarter of the memory,
  within safe limits), so one Nestfile works on a MacBook Air and a Mac Studio.
- **Machine names:** letters, digits, `-`, `_`, `.`; must start with a letter or digit.
- **Ports:** a host port can be forwarded only once across all machines; ports below 1024 warn.
- **Paths** in `shares`, `provision` and `hooks` must exist; hook scripts must be executable.

## Running

```bash
nestctl validate --strict   # check against this Mac (CI-friendly)
nestctl up                  # create missing machines, start all, Ctrl-C shuts them down
```

`nestctl up` creates each missing machine from its catalog cloud image and provisions it with cloud-init:
your user with your SSH keys, every share mounted at `/mnt/<tag>`, Rosetta when enabled, plus the
project’s own `provision.cloudInit` file. When the guest reports ready, `postProvision` hooks run once.
Existing machines are started as they are. Details: [images.md](images.md).
