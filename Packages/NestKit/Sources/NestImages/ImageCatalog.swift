// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

/// An operating system image published by a distribution for ARM64 (aarch64).
///
/// Only official distribution servers are listed, always over HTTPS. The actual file name is resolved
/// at download time from the distribution’s own checksum list or directory, so the catalog keeps
/// working across point releases, and every download is verified against the published checksum.
public struct CatalogImage: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Boots directly and is configured on first boot by cloud-init. Ready in about a minute.
        case cloud
        /// An installer ISO; you install the system interactively.
        case installer
    }

    public enum Format: String, Hashable, Sendable, Codable {
        /// A tar archive (gzip or xz) containing a raw disk image.
        case tarRaw
        /// A qcow2 (copy-on-write) v2/v3 image, converted to a raw disk after download.
        case qcow2
        /// A bootable installer ISO, used as is.
        case iso
    }

    /// How to find the current file and its checksum on the distribution’s server.
    public enum Source: Hashable, Sendable {
        /// A checksum list (`SHA256SUMS`, `CHECKSUM`, …) in the same folder as the file.
        case checksumList(URL, file: String)
        /// A folder index containing a versioned checksum list (e.g. Fedora’s `…-CHECKSUM`).
        case indexedChecksumList(index: URL, list: String, file: String)
        /// A fixed file name with a checksum file next to it (`file.sha256`).
        case fileWithChecksum(URL, checksumSuffix: String)
        /// The newest file in a folder index matching a pattern, with a checksum file next to it.
        case indexedFile(index: URL, file: String, checksumSuffix: String)
        /// A text file naming the latest build (Gentoo’s `latest-iso.txt`).
        case latestPointer(URL, file: String, checksumSuffix: String)
    }

    /// Stable identifier used in Nestfiles and on the command line, e.g. `ubuntu-24.04`.
    public let id: String
    public let aliases: [String]
    public let family: String
    public let displayName: String
    public let kind: Kind
    public let format: Format
    public let source: Source
    /// Approximate download size, shown before downloading.
    public let downloadSize: ByteCount
    public let minimumDiskSize: ByteCount
    public var guest: GuestOperatingSystem {
        .linux
    }

    /// The distribution server the image comes from, shown to users.
    public var sourceHost: String {
        let url: URL = switch source {
        case let .checksumList(url, _), let .fileWithChecksum(url, _), let .latestPointer(url, _, _): url
        case let .indexedChecksumList(index, _, _), let .indexedFile(index, _, _): index
        }
        return url.host() ?? ""
    }
}

public enum ImageCatalog {
    // The catalog is plain data; see docs/images.md for how entries are chosen and verified.
    // swiftlint:disable force_unwrapping
    public static let all: [CatalogImage] = {
        func url(_ string: String) -> URL {
            URL(string: string)!
        }
        // Identifier, distribution family and display name of one entry.
        struct Name {
            let id: String
            let family: String
            let displayName: String

            init(_ id: String, _ family: String, _ displayName: String) {
                self.id = id
                self.family = family
                self.displayName = displayName
            }
        }
        func cloud(
            _ name: Name, _ format: CatalogImage.Format, _ source: CatalogImage.Source, megabytes: UInt64,
            aliases: [String] = []
        ) -> CatalogImage {
            CatalogImage(
                id: name.id, aliases: aliases, family: name.family, displayName: name.displayName, kind: .cloud,
                format: format, source: source, downloadSize: .mebibytes(megabytes), minimumDiskSize: .gibibytes(8)
            )
        }
        func installer(
            _ name: Name, _ source: CatalogImage.Source, megabytes: UInt64, aliases: [String] = []
        ) -> CatalogImage {
            CatalogImage(
                id: name.id, aliases: aliases, family: name.family, displayName: name.displayName, kind: .installer,
                format: .iso, source: source, downloadSize: .mebibytes(megabytes), minimumDiskSize: .gibibytes(16)
            )
        }
        return [
            // MARK: Cloud images — ready in about a minute, configured by cloud-init

            // Ubuntu’s .tar.gz holds only the root file system; the bootable disk is the qcow2 .img.
            cloud(Name("ubuntu-26.04", "Ubuntu", "Ubuntu 26.04 LTS"), .qcow2, .checksumList(
                url("https://cloud-images.ubuntu.com/resolute/current/SHA256SUMS"),
                file: #"resolute-server-cloudimg-arm64\.img"#
            ), megabytes: 900, aliases: ["ubuntu"]),
            cloud(Name("ubuntu-24.04", "Ubuntu", "Ubuntu 24.04 LTS"), .qcow2, .checksumList(
                url("https://cloud-images.ubuntu.com/noble/current/SHA256SUMS"),
                file: #"noble-server-cloudimg-arm64\.img"#
            ), megabytes: 588),
            cloud(Name("debian-13", "Debian", "Debian 13 “Trixie”"), .tarRaw, .checksumList(
                url("https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS"),
                file: #"debian-13-genericcloud-arm64\.tar\.xz"#
            ), megabytes: 204, aliases: ["debian", "trixie"]),
            cloud(Name("debian-12", "Debian", "Debian 12 “Bookworm”"), .tarRaw, .checksumList(
                url("https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"),
                file: #"debian-12-genericcloud-arm64\.tar\.xz"#
            ), megabytes: 201, aliases: ["bookworm"]),
            cloud(Name("fedora-44", "Fedora", "Fedora 44 Cloud"), .qcow2, .indexedChecksumList(
                index: url("https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/aarch64/images/"),
                list: #"Fedora-Cloud-44-.*-aarch64-CHECKSUM"#,
                file: #"Fedora-Cloud-Base-Generic-44-.*\.aarch64\.qcow2"#
            ), megabytes: 503, aliases: ["fedora"]),
            cloud(Name("almalinux-10", "AlmaLinux", "AlmaLinux 10"), .qcow2, .checksumList(
                url("https://repo.almalinux.org/almalinux/10/cloud/aarch64/images/CHECKSUM"),
                file: #"AlmaLinux-10-GenericCloud-latest\.aarch64\.qcow2"#
            ), megabytes: 456, aliases: ["almalinux", "alma"]),
            cloud(Name("almalinux-9", "AlmaLinux", "AlmaLinux 9"), .qcow2, .checksumList(
                url("https://repo.almalinux.org/almalinux/9/cloud/aarch64/images/CHECKSUM"),
                file: #"AlmaLinux-9-GenericCloud-latest\.aarch64\.qcow2"#
            ), megabytes: 432),
            cloud(Name("rocky-10", "Rocky Linux", "Rocky Linux 10"), .qcow2, .checksumList(
                url("https://dl.rockylinux.org/pub/rocky/10/images/aarch64/CHECKSUM"),
                file: #"Rocky-10-GenericCloud-Base\.latest\.aarch64\.qcow2"#
            ), megabytes: 447, aliases: ["rocky", "rockylinux"]),
            cloud(Name("rocky-9", "Rocky Linux", "Rocky Linux 9"), .qcow2, .checksumList(
                url("https://dl.rockylinux.org/pub/rocky/9/images/aarch64/CHECKSUM"),
                file: #"Rocky-9-GenericCloud-Base\.latest\.aarch64\.qcow2"#
            ), megabytes: 495),
            cloud(Name("centos-stream-10", "CentOS", "CentOS Stream 10"), .qcow2, .checksumList(
                url("https://cloud.centos.org/centos/10-stream/aarch64/images/CHECKSUM"),
                file: #"CentOS-Stream-GenericCloud-10-latest\.aarch64\.qcow2"#
            ), megabytes: 844, aliases: ["centos", "centos-stream"]),
            cloud(Name("centos-stream-9", "CentOS", "CentOS Stream 9"), .qcow2, .checksumList(
                url("https://cloud.centos.org/centos/9-stream/aarch64/images/CHECKSUM"),
                file: #"CentOS-Stream-GenericCloud-9-latest\.aarch64\.qcow2"#
            ), megabytes: 1136),
            cloud(Name("opensuse-tumbleweed", "openSUSE", "openSUSE Tumbleweed"), .qcow2, .fileWithChecksum(
                url(
                    "https://download.opensuse.org/ports/aarch64/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.aarch64-Cloud.qcow2"
                ),
                checksumSuffix: ".sha256"
            ), megabytes: 276, aliases: ["opensuse", "tumbleweed"]),
            cloud(Name("alpine-3.24", "Alpine Linux", "Alpine Linux 3.24"), .tarRaw, .indexedFile(
                index: url("https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/cloud/"),
                file: #"alpine-3\.24\.\d+-aarch64-cloudinit-metal-r\d+\.raw\.tar\.gz"#,
                checksumSuffix: ".sha512"
            ), megabytes: 545, aliases: ["alpine"]),
            cloud(Name("kali", "Kali Linux", "Kali Linux (rolling)"), .tarRaw, .checksumList(
                url("https://kali.download/cloud-images/current/SHA256SUMS"),
                file: #"kali-linux-\d{4}\.\d+-cloud-genericcloud-arm64\.tar\.xz"#
            ), megabytes: 217),

            // MARK: Installer ISOs — interactive installation

            installer(Name("ubuntu-26.04-server", "Ubuntu", "Ubuntu Server 26.04 LTS installer"), .checksumList(
                url("https://cdimage.ubuntu.com/releases/26.04/release/SHA256SUMS"),
                file: #"ubuntu-26\.04(\.\d+)?-live-server-arm64\.iso"#
            ), megabytes: 2934),
            installer(Name("ubuntu-24.04-server", "Ubuntu", "Ubuntu Server 24.04 LTS installer"), .checksumList(
                url("https://cdimage.ubuntu.com/releases/24.04/release/SHA256SUMS"),
                file: #"ubuntu-24\.04(\.\d+)?-live-server-arm64\.iso"#
            ), megabytes: 3648),
            installer(Name("debian-13-netinst", "Debian", "Debian 13 network installer"), .checksumList(
                url("https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/SHA512SUMS"),
                file: #"debian-13\.\d+\.\d+-arm64-netinst\.iso"#
            ), megabytes: 701),
            installer(Name("fedora-44-server", "Fedora", "Fedora Server 44 network installer"), .indexedChecksumList(
                index: url("https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Server/aarch64/iso/"),
                list: #"Fedora-Server-44-.*-aarch64-CHECKSUM"#,
                file: #"Fedora-Server-netinst-aarch64-44-.*\.iso"#
            ), megabytes: 1199),
            installer(Name("almalinux-10-boot", "AlmaLinux", "AlmaLinux 10 boot installer"), .checksumList(
                url("https://repo.almalinux.org/almalinux/10/isos/aarch64/CHECKSUM"),
                file: #"AlmaLinux-10-latest-aarch64-boot\.iso"#
            ), megabytes: 1075),
            installer(Name("almalinux-9-boot", "AlmaLinux", "AlmaLinux 9 boot installer"), .checksumList(
                url("https://repo.almalinux.org/almalinux/9/isos/aarch64/CHECKSUM"),
                file: #"AlmaLinux-9-latest-aarch64-boot\.iso"#
            ), megabytes: 1390),
            installer(Name("rocky-10-minimal", "Rocky Linux", "Rocky Linux 10 minimal installer"), .checksumList(
                url("https://download.rockylinux.org/pub/rocky/10/isos/aarch64/CHECKSUM"),
                file: #"Rocky-10-latest-aarch64-minimal\.iso"#
            ), megabytes: 2286),
            installer(Name("rocky-9-minimal", "Rocky Linux", "Rocky Linux 9 minimal installer"), .checksumList(
                url("https://download.rockylinux.org/pub/rocky/9/isos/aarch64/CHECKSUM"),
                file: #"Rocky-9-latest-aarch64-minimal\.iso"#
            ), megabytes: 2416),
            installer(Name("centos-stream-10-boot", "CentOS", "CentOS Stream 10 boot installer"), .fileWithChecksum(
                url(
                    "https://mirror.stream.centos.org/10-stream/BaseOS/aarch64/iso/CentOS-Stream-10-latest-aarch64-boot.iso"
                ),
                checksumSuffix: ".SHA256SUM"
            ), megabytes: 979),
            installer(Name("centos-stream-9-boot", "CentOS", "CentOS Stream 9 boot installer"), .fileWithChecksum(
                url(
                    "https://mirror.stream.centos.org/9-stream/BaseOS/aarch64/iso/CentOS-Stream-9-latest-aarch64-boot.iso"
                ),
                checksumSuffix: ".SHA256SUM"
            ), megabytes: 1467),
            installer(Name("alpine-3.24-virt", "Alpine Linux", "Alpine Linux 3.24 (virt)"), .indexedFile(
                index: url("https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/"),
                file: #"alpine-virt-3\.24\.\d+-aarch64\.iso"#,
                checksumSuffix: ".sha256"
            ), megabytes: 89),
            installer(Name(
                "opensuse-tumbleweed-net", "openSUSE", "openSUSE Tumbleweed network installer"
            ), .fileWithChecksum(
                url(
                    "https://download.opensuse.org/ports/aarch64/tumbleweed/iso/openSUSE-Tumbleweed-NET-aarch64-Current.iso"
                ),
                checksumSuffix: ".sha256"
            ), megabytes: 434),
            installer(Name("kali-installer", "Kali Linux", "Kali Linux installer"), .checksumList(
                url("https://cdimage.kali.org/current/SHA256SUMS"),
                file: #"kali-linux-\d{4}\.\d+-installer-arm64\.iso"#
            ), megabytes: 3863),
            installer(Name("nixos-minimal", "NixOS", "NixOS 25.11 minimal installer"), .fileWithChecksum(
                url("https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso"),
                checksumSuffix: ".sha256"
            ), megabytes: 1634, aliases: ["nixos"]),
            installer(Name("gentoo-minimal", "Gentoo", "Gentoo minimal installer"), .latestPointer(
                url("https://distfiles.gentoo.org/releases/arm64/autobuilds/latest-iso.txt"),
                file: #".*install-arm64-minimal.*\.iso"#,
                checksumSuffix: ".sha256"
            ), megabytes: 816, aliases: ["gentoo"]),
            installer(Name("grml", "Grml", "Grml live system (rescue)"), .indexedFile(
                index: url("https://download.grml.org/"),
                file: #"grml-full-\d{4}\.\d+-arm64\.iso"#,
                checksumSuffix: ".sha256"
            ), megabytes: 1041, aliases: ["grml-full"]),
        ]
    }()

    // swiftlint:enable force_unwrapping

    /// Finds an image by id or alias, case-insensitively.
    public static func image(named name: String) -> CatalogImage? {
        let key = name.lowercased()
        return all.first { $0.id == key } ?? all.first { $0.aliases.contains(key) }
    }

    public static func images(of kind: CatalogImage.Kind) -> [CatalogImage] {
        all.filter { $0.kind == kind }
    }
}

/// Parses checksum files: GNU (`hash  name`, `hash *name`), BSD (`SHA256 (name) = hash`) and
/// bare single-hash files (key `""`).
public enum ChecksumFile {
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let bsd = parseBSD(line) {
                result[bsd.name] = bsd.hash
                continue
            }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard let first = parts.first, isHash(first) else { continue }
            guard parts.count == 2 else {
                result[""] = first.lowercased()
                continue
            }
            var name = parts[1].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") {
                name.removeFirst()
            }
            if name.hasPrefix("./") {
                name.removeFirst(2)
            }
            result[name] = first.lowercased()
        }
        return result
    }

    private static func parseBSD(_ line: String) -> (name: String, hash: String)? {
        guard line.hasPrefix("SHA"), let open = line.firstIndex(of: "("),
              let close = line.range(of: ") = ", options: .backwards)
        else { return nil }
        var name = String(line[line.index(after: open) ..< close.lowerBound])
        if name.hasPrefix("./") {
            name.removeFirst(2)
        }
        let hash = line[close.upperBound...]
        return isHash(hash) ? (name, hash.lowercased()) : nil
    }

    static func isHash(_ text: some StringProtocol) -> Bool {
        (text.count == 64 || text.count == 128) && text.allSatisfy(\.isHexDigit)
    }
}
