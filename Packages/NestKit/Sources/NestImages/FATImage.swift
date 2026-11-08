// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// Writes a small FAT12 volume (1.44 MB layout) with long file names.
///
/// Used for the cloud-init NoCloud seed (`CIDATA`). Writing it ourselves avoids shelling out to
/// `hdiutil`/`newfs_msdos`, works inside the App Sandbox and is fully unit-testable.
/// Layout: 1 boot sector, 2 × 9 FAT sectors, 14 root directory sectors (224 entries), data clusters
/// of one sector each.
public struct FATImage {
    public enum WriteError: Error, Equatable, Sendable {
        case tooLarge(bytes: Int, capacity: Int)
        case tooManyFiles
        case invalidLabel
    }

    static let bytesPerSector = 512
    static let totalSectors = 2880
    static let sectorsPerFAT = 9
    static let rootEntries = 224
    static let firstFATSector = 1
    static let rootSector = firstFATSector + 2 * sectorsPerFAT // 19
    static let firstDataSector = rootSector + rootEntries * 32 / bytesPerSector // 33
    static let dataClusters = totalSectors - firstDataSector

    public var label: String
    public private(set) var files: [(name: String, contents: Data)] = []

    public init(label: String) {
        self.label = label
    }

    public mutating func add(_ name: String, contents: Data) {
        files.append((name, contents))
    }

    public mutating func add(_ name: String, text: String) {
        add(name, contents: Data(text.utf8))
    }

    /// The complete volume image.
    public func data(
        volumeID: UInt32 = 0x4E53_5354,
        date: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) throws -> Data {
        let labelBytes = Array(label.uppercased().utf8)
        guard (1 ... 11).contains(labelBytes.count) else { throw WriteError.invalidLabel }
        let clustersNeeded = files.reduce(0) { $0 + max(
            1,
            ($1.contents.count + Self.bytesPerSector - 1) / Self.bytesPerSector
        ) }
        guard clustersNeeded <= Self.dataClusters else {
            throw WriteError.tooLarge(
                bytes: files.reduce(0) { $0 + $1.contents.count },
                capacity: Self.dataClusters * Self.bytesPerSector
            )
        }

        var image = [UInt8](repeating: 0, count: Self.totalSectors * Self.bytesPerSector)
        writeBootSector(into: &image, label: labelBytes, volumeID: volumeID)

        var fat = FATTable()
        var entries: [[UInt8]] = [Self.volumeLabelEntry(labelBytes, date: date)]
        var nextCluster = 2
        for (index, file) in files.enumerated() {
            let clusters = max(1, (file.contents.count + Self.bytesPerSector - 1) / Self.bytesPerSector)
            let first = file.contents.isEmpty ? 0 : nextCluster
            if !file.contents.isEmpty {
                for offset in 0 ..< clusters {
                    let cluster = nextCluster + offset
                    fat[cluster] = offset == clusters - 1 ? 0xFFF : UInt16(cluster + 1)
                }
                let start = (Self.firstDataSector + nextCluster - 2) * Self.bytesPerSector
                image.replaceSubrange(start ..< start + file.contents.count, with: file.contents)
                nextCluster += clusters
            }
            let short = Self.shortName(for: file.name, index: index + 1)
            entries += Self.longNameEntries(for: file.name, shortName: short)
            entries.append(Self.directoryEntry(short, firstCluster: first, size: file.contents.count, date: date))
        }
        guard entries.count <= Self.rootEntries else { throw WriteError.tooManyFiles }

        let fatBytes = fat.encoded(sectors: Self.sectorsPerFAT, bytesPerSector: Self.bytesPerSector)
        for copy in 0 ..< 2 {
            let start = (Self.firstFATSector + copy * Self.sectorsPerFAT) * Self.bytesPerSector
            image.replaceSubrange(start ..< start + fatBytes.count, with: fatBytes)
        }
        let root = entries.flatMap(\.self)
        let rootStart = Self.rootSector * Self.bytesPerSector
        image.replaceSubrange(rootStart ..< rootStart + root.count, with: root)
        return Data(image)
    }

    // MARK: - Boot sector

    private func writeBootSector(into image: inout [UInt8], label: [UInt8], volumeID: UInt32) {
        func put(_ bytes: [UInt8], at offset: Int) {
            image.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
        }
        func le16(_ value: Int) -> [UInt8] {
            [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]
        }
        func le32(_ value: UInt32) -> [UInt8] {
            (0 ..< 4).map { UInt8(value >> (8 * $0) & 0xFF) }
        }

        put([0xEB, 0x3C, 0x90], at: 0) // jump
        put(Array("NESTSUIT".utf8), at: 3) // OEM name
        put(le16(Self.bytesPerSector), at: 11)
        image[13] = 1 // sectors per cluster
        put(le16(1), at: 14) // reserved sectors
        image[16] = 2 // number of FATs
        put(le16(Self.rootEntries), at: 17)
        put(le16(Self.totalSectors), at: 19)
        image[21] = 0xF0 // media descriptor
        put(le16(Self.sectorsPerFAT), at: 22)
        put(le16(18), at: 24) // sectors per track
        put(le16(2), at: 26) // heads
        image[38] = 0x29 // extended boot signature
        put(le32(volumeID), at: 39)
        put(Self.padded(label, to: 11), at: 43)
        put(Array("FAT12   ".utf8), at: 54)
        put([0x55, 0xAA], at: 510)
    }

    // MARK: - Directory entries

    static func padded(_ bytes: [UInt8], to length: Int) -> [UInt8] {
        Array((bytes + [UInt8](repeating: 0x20, count: length)).prefix(length))
    }

    /// An 8.3 alias such as `USER-D~1`; long names carry the real file name.
    static func shortName(for name: String, index: Int) -> [UInt8] {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".utf8)
        let base = name.uppercased().utf8.filter(allowed.contains)
        let suffix = Array("~\(index)".utf8)
        return padded(Array(base.prefix(8 - suffix.count)) + suffix, to: 11)
    }

    static func checksum(of shortName: [UInt8]) -> UInt8 {
        shortName.reduce(UInt8(0)) { sum, byte in
            ((sum & 1) << 7) &+ (sum >> 1) &+ byte
        }
    }

    /// VFAT long-name entries, last part first, each holding 13 UTF-16 code units.
    static func longNameEntries(for name: String, shortName: [UInt8]) -> [[UInt8]] {
        var units = Array(name.utf16)
        units.append(0x0000)
        while units.count % 13 != 0 {
            units.append(0xFFFF)
        }
        let parts = units.count / 13
        let sum = checksum(of: shortName)
        return (0 ..< parts).reversed().map { part in
            var entry = [UInt8](repeating: 0, count: 32)
            entry[0] = UInt8(part + 1) | (part == parts - 1 ? 0x40 : 0)
            entry[11] = 0x0F // LFN attribute
            entry[13] = sum
            let chunk = units[part * 13 ..< part * 13 + 13]
            for (index, unit) in chunk.enumerated() {
                let offset = switch index {
                case 0 ..< 5: 1 + index * 2
                case 5 ..< 11: 14 + (index - 5) * 2
                default: 28 + (index - 11) * 2
                }
                entry[offset] = UInt8(unit & 0xFF)
                entry[offset + 1] = UInt8(unit >> 8)
            }
            return entry
        }
    }

    static func directoryEntry(_ shortName: [UInt8], firstCluster: Int, size: Int, date: Date) -> [UInt8] {
        var entry = [UInt8](repeating: 0, count: 32)
        entry.replaceSubrange(0 ..< 11, with: shortName)
        entry[11] = 0x20 // archive
        let (time, day) = dosTimestamp(date)
        entry.replaceSubrange(14 ..< 16, with: [UInt8(time & 0xFF), UInt8(time >> 8)])
        entry.replaceSubrange(16 ..< 18, with: [UInt8(day & 0xFF), UInt8(day >> 8)])
        entry.replaceSubrange(22 ..< 24, with: [UInt8(time & 0xFF), UInt8(time >> 8)])
        entry.replaceSubrange(24 ..< 26, with: [UInt8(day & 0xFF), UInt8(day >> 8)])
        entry.replaceSubrange(26 ..< 28, with: [UInt8(firstCluster & 0xFF), UInt8(firstCluster >> 8)])
        entry.replaceSubrange(28 ..< 32, with: (0 ..< 4).map { UInt8(size >> (8 * $0) & 0xFF) })
        return entry
    }

    static func volumeLabelEntry(_ label: [UInt8], date: Date) -> [UInt8] {
        var entry = directoryEntry(padded(label, to: 11), firstCluster: 0, size: 0, date: date)
        entry[11] = 0x08 // volume label
        return entry
    }

    static func dosTimestamp(_ date: Date) -> (time: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
        let day = ((parts.year ?? 1980) - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
        return (time, day)
    }
}

/// FAT12 allocation table: 12-bit entries packed two per three bytes.
struct FATTable {
    private var entries: [Int: UInt16] = [0: 0xFF0, 1: 0xFFF]

    subscript(cluster: Int) -> UInt16 {
        get { entries[cluster] ?? 0 }
        set { entries[cluster] = newValue }
    }

    func encoded(sectors: Int, bytesPerSector: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: sectors * bytesPerSector)
        for (cluster, value) in entries {
            let offset = cluster * 3 / 2
            if cluster.isMultiple(of: 2) {
                bytes[offset] = UInt8(value & 0xFF)
                bytes[offset + 1] = (bytes[offset + 1] & 0xF0) | UInt8(value >> 8 & 0x0F)
            } else {
                bytes[offset] = (bytes[offset] & 0x0F) | UInt8((value & 0x0F) << 4)
                bytes[offset + 1] = UInt8(value >> 4 & 0xFF)
            }
        }
        return bytes
    }
}
