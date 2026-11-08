// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Testing
@testable import NestImages

/// Minimal FAT12 reader used only to check what the writer produced.
struct FATReader {
    let image: [UInt8]

    var label: String {
        (String(bytes: image[43 ..< 54], encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }

    func le16(_ offset: Int) -> Int {
        Int(image[offset]) | Int(image[offset + 1]) << 8
    }

    func le32(_ offset: Int) -> Int {
        le16(offset) | le16(offset + 2) << 16
    }

    func fatEntry(_ cluster: Int) -> Int {
        let offset = 512 + cluster * 3 / 2
        let pair = le16(offset)
        return cluster.isMultiple(of: 2) ? pair & 0xFFF : pair >> 4
    }

    /// Long file name → contents.
    func files() -> [String: Data] {
        var result: [String: Data] = [:]
        var pendingName: [UInt16] = []
        for index in 0 ..< 224 {
            let entry = 19 * 512 + index * 32
            guard image[entry] != 0 else { break }
            if image[entry + 11] == 0x0F {
                let offsets = Array(stride(from: 1, to: 11, by: 2)) + Array(stride(from: 14, to: 26, by: 2)) + [28, 30]
                let part = offsets.map { UInt16(le16(entry + $0)) }.prefix { $0 != 0 && $0 != 0xFFFF }
                pendingName = Array(part) + pendingName
                continue
            }
            guard image[entry + 11] & 0x08 == 0 else { continue } // volume label
            let name = String(decoding: pendingName, as: UTF16.self)
            pendingName = []
            var cluster = le16(entry + 26)
            var data = Data()
            let size = le32(entry + 28)
            while cluster >= 2, cluster < 0xFF8, data.count < size {
                let start = (33 + cluster - 2) * 512
                data.append(contentsOf: image[start ..< start + 512])
                cluster = fatEntry(cluster)
            }
            result[name] = data.prefix(size)
        }
        return result
    }
}

@Suite("cloud-init seed")
struct SeedTests {
    let seed = CloudInitSeed(
        instanceID: "1234", hostname: "Dev Box!", userName: "Chris.Reit",
        sshKeys: ["ssh-ed25519 AAAAC3 key@mac"], shares: [.init(tag: "workspace")], rosetta: true
    )

    @Test("the volume is FAT12, labelled CIDATA, with long file names and exact contents")
    func volume() throws {
        let reader = try FATReader(image: Array(seed.volume()))
        #expect(reader.image[510] == 0x55 && reader.image[511] == 0xAA)
        #expect(reader.label == "CIDATA")
        let files = reader.files()
        #expect(Set(files.keys) == ["meta-data", "user-data"])
        #expect(files["meta-data"] == Data(seed.metaData.utf8))
        #expect(files["user-data"] == Data(seed.userData.utf8))
    }

    @Test("files larger than one cluster are chained correctly")
    func multiCluster() throws {
        var image = FATImage(label: "TEST")
        let big = Data((0 ..< 5000).map { UInt8($0 % 251) })
        image.add("big-file.bin", contents: big)
        image.add("small.txt", text: "hi")
        let files = try FATReader(image: Array(image.data())).files()
        #expect(files["big-file.bin"] == big)
        #expect(files["small.txt"] == Data("hi".utf8))
    }

    @Test("oversized content is rejected")
    func tooLarge() {
        var image = FATImage(label: "TEST")
        image.add("huge", contents: Data(count: 2 * 1024 * 1024))
        #expect(throws: FATImage.WriteError.self) { try image.data() }
    }

    @Test("the long-name checksum matches the FAT specification’s reference algorithm", arguments: [
        "USER-D~1   ", "META-D~2   ", "README  TXT", "A          ",
    ])
    func checksum(shortName: String) {
        // Reference: “Sum = ((Sum & 1) ? 0x80 : 0) + (Sum >> 1) + *pFcbName++” (Microsoft FAT spec),
        // written with Int arithmetic and an explicit modulo, independent of the writer’s UInt8 code.
        var reference = 0
        for byte in shortName.utf8 {
            reference = ((reference & 1) != 0 ? 0x80 : 0) + (reference >> 1) + Int(byte)
            reference %= 256
        }
        #expect(Int(FATImage.checksum(of: Array(shortName.utf8))) == reference)
    }

    @Test("host and user names are sanitized for Linux")
    func sanitizing() {
        #expect(seed.hostname == "dev-box")
        #expect(seed.userName == "chrisreit")
        #expect(CloudInitSeed.sanitizedUserName("123") == "nest")
    }

    @Test("user-data sets up the user, shares, Rosetta and the readiness report")
    func userData() {
        let data = seed.userData
        #expect(data.hasPrefix("#cloud-config\n"))
        #expect(data.contains("name: chrisreit"))
        #expect(data.contains("\"ssh-ed25519 AAAAC3 key@mac\""))
        #expect(data.contains("[workspace, /mnt/workspace, virtiofs"))
        #expect(data.contains("[rosetta, /media/rosetta, virtiofs"))
        #expect(data.contains(":rosetta:M::\\x7fELF"))
        #expect(data.contains(CloudInitSeed.readyMarker))
    }

    @Test("a password is stored only as a hash and unlocks console login")
    func password() {
        var withPassword = seed
        withPassword.passwordHash = SHA512Crypt.hash("correct horse", salt: "abcdefgh")
        #expect(withPassword.userData.contains("lock_passwd: false"))
        #expect(withPassword.userData.contains("passwd: \"$6$abcdefgh$"))
        #expect(!withPassword.userData.contains("correct horse"))
        #expect(seed.userData.contains("lock_passwd: true"))
    }

    @Test("a project cloud-config is added as a second MIME part")
    func multipart() {
        var withProject = seed
        withProject.additionalUserData = "#cloud-config\npackages: [git]\n"
        let data = withProject.userData
        #expect(data.hasPrefix("Content-Type: multipart/mixed"))
        #expect(data.components(separatedBy: "Content-Type: text/cloud-config").count == 3)
        #expect(data.contains("packages: [git]"))
    }

    @Test("the readiness report is read from the console log")
    func readyReport() throws {
        let log = FileManager.default.temporaryDirectory.appending(path: "console-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        try Data("booting…\n\u{1B}[0mNESTSUITE-READY share:workspace=ok rosetta=ok\nlogin:".utf8).write(to: log)
        #expect(MachineProvisioner.readyReport(in: log) == "share:workspace=ok rosetta=ok")
    }

    @Test("a disk from a base image is a clone grown to the requested size")
    func diskProvisioning() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = folder.appending(path: "base.raw")
        try Data(repeating: 7, count: 8192).write(to: base)
        let disk = folder.appending(path: "Disk.img")
        try DiskProvisioner.createDisk(from: base, at: disk, size: .mebibytes(64))
        let attributes = try FileManager.default.attributesOfItem(atPath: disk.path(percentEncoded: false))
        #expect(attributes[.size] as? Int == 64 * 1024 * 1024)
        #expect(try Data(contentsOf: disk).prefix(8192) == Data(repeating: 7, count: 8192))
        #expect(try Data(contentsOf: base).count == 8192, "the base image stays untouched")
    }
}
