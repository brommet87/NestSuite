# `Nestfile.yml` reference

A Nestfile describes one or more machines for a project. Commit it next to your code; teammates get
the same environment. File names searched: `Nestfile.yml`, `Nestfile.yaml`, `Nestfile`.

```yaml
version: 1
machines:
  dev:
    guest: linux              # linux | macOS            (required)
    image: ubuntu-24.04       # catalog id, ISO path or URL (from 0.2)
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

Check a file with `nestctl validate` (add `--strict` in CI). In 0.1, Nestfiles are parsed and
validated; `nestctl up` creates and starts machines from them in 0.2.
