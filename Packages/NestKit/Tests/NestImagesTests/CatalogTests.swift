// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestImages

@Suite("Image catalog")
struct CatalogTests {
    @Test("ids and aliases are unique")
    func unique() {
        let names = ImageCatalog.all.flatMap { [$0.id] + $0.aliases }
        #expect(Set(names).count == names.count)
    }

    @Test("every source is an official HTTPS server and every pattern is a valid regex")
    func sources() throws {
        for image in ImageCatalog.all {
            #expect(!image.sourceHost.isEmpty, "\(image.id)")
            let (urls, patterns): ([URL], [String]) = switch image.source {
            case let .checksumList(url, file): ([url], [file])
            case let .indexedChecksumList(index, list, file): ([index], [list, file])
            case let .fileWithChecksum(url, _): ([url], [])
            case let .indexedFile(index, file, _): ([index], [file])
            case let .latestPointer(url, file, _): ([url], [file])
            }
            #expect(urls.allSatisfy { $0.scheme == "https" }, "\(image.id) must use HTTPS")
            for pattern in patterns {
                _ = try Regex(pattern)
            }
        }
    }

    @Test("installers are ISOs, cloud images are disks")
    func kinds() {
        for image in ImageCatalog.all {
            #expect((image.kind == .installer) == (image.format == .iso), "\(image.id)")
        }
        #expect(ImageCatalog.images(of: .cloud).count >= 10)
        #expect(ImageCatalog.images(of: .installer).count >= 10)
    }

    @Test("lookup by id or alias, case-insensitively; ids win over aliases")
    func lookup() {
        #expect(ImageCatalog.image(named: "Debian")?.id == "debian-13")
        #expect(ImageCatalog.image(named: "ubuntu-24.04")?.id == "ubuntu-24.04")
        #expect(ImageCatalog.image(named: "trixie")?.id == "debian-13")
        #expect(ImageCatalog.image(named: "windows") == nil)
    }
}

@Suite("Checksum files")
struct ChecksumFileTests {
    let sha256 = String(repeating: "ab", count: 32)
    let sha512 = String(repeating: "cd", count: 64)

    @Test("GNU format with text and binary markers")
    func gnu() {
        let parsed = ChecksumFile.parse("\(sha256)  disk.tar.gz\n\(sha512) *other.iso\n# comment\n")
        #expect(parsed == ["disk.tar.gz": sha256, "other.iso": sha512])
    }

    @Test("BSD format as used by RHEL-family distributions")
    func bsd() {
        let parsed = ChecksumFile.parse("# AlmaLinux\nSHA256 (AlmaLinux-10.qcow2) = \(sha256.uppercased())\n")
        #expect(parsed == ["AlmaLinux-10.qcow2": sha256])
    }

    @Test("a file containing only a hash")
    func bare() {
        #expect(ChecksumFile.parse("\(sha512)\n") == ["": sha512])
    }

    @Test("garbage is ignored")
    func garbage() {
        #expect(ChecksumFile.parse("not a checksum\nabc  file\n").isEmpty)
    }
}
