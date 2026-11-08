// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

/// The first-boot configuration for cloud images (cloud-init “NoCloud” data source).
///
/// NestSuite sets up what every machine needs — a user with your SSH keys, shared folders mounted,
/// Rosetta registered — and reports back over the serial console when the guest is ready. A project’s
/// own `cloud-init.yaml` is added as a second part and merged by cloud-init.
public struct CloudInitSeed: Equatable, Sendable {
    /// Printed to the serial console when provisioning finished, followed by check results.
    public static let readyMarker = "NESTSUITE-READY"
    public static let rosettaMountPoint = "/media/rosetta"

    public struct Share: Equatable, Sendable {
        public let tag: String
        public let mountPoint: String

        public init(tag: String, mountPoint: String? = nil) {
            self.tag = tag
            self.mountPoint = mountPoint ?? "/mnt/\(tag)"
        }
    }

    public var instanceID: String
    public var hostname: String
    public var userName: String
    public var sshKeys: [String]
    public var shares: [Share]
    public var rosetta: Bool
    /// A SHA-512-crypt hash (`$6$…`, see ``SHA512Crypt``) for console login; `nil` = SSH keys only.
    public var passwordHash: String?
    /// The project’s own cloud-config (`provision.cloudInit`), if any.
    public var additionalUserData: String?

    public init(
        instanceID: String, hostname: String, userName: String, sshKeys: [String] = [],
        shares: [Share] = [], rosetta: Bool = false, passwordHash: String? = nil, additionalUserData: String? = nil
    ) {
        self.instanceID = instanceID
        self.hostname = Self.sanitizedHostname(hostname)
        self.userName = Self.sanitizedUserName(userName)
        self.sshKeys = sshKeys
        self.shares = shares
        self.rosetta = rosetta
        self.passwordHash = passwordHash
        self.additionalUserData = additionalUserData
    }

    public var metaData: String {
        "instance-id: \(instanceID)\nlocal-hostname: \(hostname)\n"
    }

    /// Our cloud-config; combined with the project’s as MIME multipart when present.
    public var userData: String {
        guard let additional = additionalUserData else { return nestSuiteConfig }
        let boundary = "NestSuite-\(instanceID)"
        return """
        Content-Type: multipart/mixed; boundary="\(boundary)"
        MIME-Version: 1.0

        --\(boundary)
        Content-Type: text/cloud-config; charset="utf-8"
        Content-Disposition: attachment; filename="nestsuite.yaml"

        \(nestSuiteConfig)
        --\(boundary)
        Content-Type: text/cloud-config; charset="utf-8"
        Content-Disposition: attachment; filename="project.yaml"
        Merge-Type: list(append)+dict(no_replace,recurse_list)+str()

        \(additional)
        --\(boundary)--

        """
    }

    var nestSuiteConfig: String {
        var lines = [
            "#cloud-config",
            "hostname: \(hostname)",
            "users:",
            "  - default",
            "  - name: \(userName)",
            "    groups: [sudo]",
            "    shell: /bin/bash",
            "    sudo: \"ALL=(ALL) NOPASSWD:ALL\"",
        ]
        if let passwordHash {
            lines += ["    lock_passwd: false", "    passwd: \(Self.quoted(passwordHash))"]
        } else {
            lines.append("    lock_passwd: true")
        }
        if !sshKeys.isEmpty {
            lines.append("    ssh_authorized_keys:")
            lines += sshKeys.map { "      - \(Self.quoted($0))" }
        }
        var mounts = shares.map { "  - [\($0.tag), \($0.mountPoint), virtiofs, \"rw,nofail\", \"0\", \"0\"]" }
        if rosetta {
            mounts.append("  - [rosetta, \(Self.rosettaMountPoint), virtiofs, \"ro,nofail\", \"0\", \"0\"]")
            lines += [
                "write_files:",
                "  - path: /etc/binfmt.d/rosetta.conf",
                "    content: |",
                "      \(Self.rosettaBinfmt)",
            ]
        }
        if !mounts.isEmpty {
            lines.append("mounts:")
            lines += mounts
        }
        lines.append("runcmd:")
        if rosetta {
            lines.append("  - [sh, -c, \(Self.quoted(Self.rosettaActivation))]")
        }
        lines.append("  - [sh, -c, \(Self.quoted(readyReport))]")
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line on the serial console: `NESTSUITE-READY share:workspace=ok rosetta=ok`.
    var readyReport: String {
        var checks = shares.map { share in
            "share:\(share.tag)=$(mountpoint -q \(share.mountPoint) && echo ok || echo missing)"
        }
        if rosetta {
            checks.append("rosetta=$([ -e /proc/sys/fs/binfmt_misc/rosetta ] && echo ok || echo missing)")
        }
        return "echo \"\(Self.readyMarker) \(checks.joined(separator: " "))\" > /dev/hvc0"
    }

    /// Activates Rosetta after the shares are mounted. On SELinux systems (Fedora, RHEL family) the
    /// share needs the `bin_t` context, or the kernel may not open the interpreter; the fstab entry is
    /// updated so this survives reboots. Other systems are left untouched (they may reject the option).
    static let rosettaActivation = [
        "if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then",
        "sed -i 's#\\(/media/rosetta[[:space:]]\\+virtiofs[[:space:]]\\+ro,nofail\\)"
            + "#\\1,context=system_u:object_r:bin_t:s0#' /etc/fstab;",
        "umount /media/rosetta; mount /media/rosetta;",
        "fi;",
        "systemctl restart systemd-binfmt || true",
    ].joined(separator: " ")

    /// Registers Rosetta for x86-64 ELF binaries (Apple’s documented binfmt pattern).
    /// Fields: name, type (magic), offset, magic bytes, mask, interpreter, flags.
    static let rosettaBinfmt = [
        ":rosetta:M:",
        #":\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00"#,
        #":\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff"#,
        ":/media/rosetta/rosetta:CF",
    ].joined()

    /// The seed volume: FAT12 labelled `CIDATA` with `user-data` and `meta-data`.
    public func volume() throws -> Data {
        var image = FATImage(label: "CIDATA")
        image.add("meta-data", text: metaData)
        image.add("user-data", text: userData)
        return try image.data()
    }

    // MARK: - Helpers

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func sanitizedHostname(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let cleaned = String(name.lowercased().map { allowed.contains($0) ? $0 : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "nestsuite" : String(cleaned.prefix(63))
    }

    public static func sanitizedUserName(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        let cleaned = String(name.lowercased().filter { allowed.contains($0) })
        guard let first = cleaned.first, first.isLetter || first == "_" else { return "nest" }
        return String(cleaned.prefix(32))
    }

    /// The Mac user’s public SSH keys (`~/.ssh/*.pub`).
    public static func localSSHKeys(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let folder = home.appending(path: ".ssh", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "pub" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("ssh-") || $0.hasPrefix("ecdsa-") || $0.hasPrefix("sk-") }
    }
}
