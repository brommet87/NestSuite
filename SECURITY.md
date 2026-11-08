# Security Policy

NestSuite runs other operating systems on your Mac. We take the isolation between guest and host
seriously and appreciate responsible disclosure.

## Supported versions

| Version | Supported |
|---|---|
| `main` / latest release | ✅ |
| older releases | ❌ |

## Reporting a vulnerability

**Please do not open a public issue.** Report vulnerabilities privately through
[GitHub Security Advisories](https://github.com/brommet87/NestSuite/security/advisories/new).

Please include:
- affected version or commit, macOS version and Mac model
- a description of the issue and its impact (e.g. guest-to-host escape, sandbox bypass, data exposure)
- steps to reproduce or a proof of concept

We aim to acknowledge reports within **3 working days** and to provide a fix or mitigation plan
within **30 days**, depending on severity. We credit reporters in the release notes unless you
prefer to stay anonymous.

## Security design

- The app runs in the **App Sandbox** with the minimum entitlements it needs
  (see [`App/NestSuite.entitlements`](App/NestSuite.entitlements) and ADR 0005).
- Virtualization is provided by Apple’s `Virtualization.framework`; guests never get direct access
  to host files except folders the user explicitly shares (security-scoped bookmarks).
- Shared folders and the shared clipboard are per-VM settings and can be turned off.
- Downloaded OS images are verified against published checksums before use (from 0.2).

Vulnerabilities in Apple’s frameworks themselves should be reported to
[Apple Product Security](https://security.apple.com/).
