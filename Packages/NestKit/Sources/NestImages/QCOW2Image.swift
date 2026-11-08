// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Compression
import Foundation

/// Reads qcow2 copy-on-write images (versions 2 and 3) and writes them as sparse raw disks.
///
/// Many distributions publish their ARM64 cloud images only in this format, while
/// `Virtualization.framework` needs raw disks. This is an independent implementation of the published
/// format specification (header, two-level cluster tables, deflate-compressed clusters); it does not
/// use any third-party code or tools.
///
/// Supported: v2/v3, standard and deflate-compressed clusters, zero clusters, any cluster size.
/// Not supported (rejected with a clear error): backing files, encryption, external data files,
/// extended L2 entries, zstd compression.
public struct QCOW2Image {
    public enum QCOW2Error: Error, Equatable, Sendable, CustomStringConvertible {
        case notQCOW2
        case unsupportedVersion(UInt32)
        case unsupportedFeature(String)
        case corrupt(String)

        public var description: String {
            switch self {
            case .notQCOW2: "not a qcow2 image"
            case let .unsupportedVersion(version): "qcow2 version \(version) is not supported"
            case let .unsupportedFeature(feature): "qcow2 feature not supported: \(feature)"
            case let .corrupt(detail): "the qcow2 image is damaged: \(detail)"
            }
        }
    }

    static let magic: UInt32 = 0x5146_49FB // "QFI\xfb"
    static let offsetMask: UInt64 = 0x00FF_FFFF_FFFF_FE00 // bits 9–55
    static let compressedFlag: UInt64 = 1 << 62

    public let url: URL
    public let version: UInt32
    public let clusterBits: UInt32
    public let virtualSize: UInt64
    let l1Size: UInt32
    let l1TableOffset: UInt64

    public var clusterSize: Int {
        1 << Int(clusterBits)
    }

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try Self.read(handle, at: 0, count: 112)
        guard header.count >= 72, header.uint32(at: 0) == Self.magic else { throw QCOW2Error.notQCOW2 }

        version = header.uint32(at: 4)
        guard version == 2 || version == 3 else { throw QCOW2Error.unsupportedVersion(version) }
        guard header.uint64(at: 8) == 0 else { throw QCOW2Error.unsupportedFeature("backing file") }
        clusterBits = header.uint32(at: 20)
        guard (9 ... 21).contains(clusterBits) else { throw QCOW2Error.corrupt("cluster size 2^\(clusterBits)") }
        virtualSize = header.uint64(at: 24)
        guard header.uint32(at: 32) == 0 else { throw QCOW2Error.unsupportedFeature("encryption") }
        l1Size = header.uint32(at: 36)
        l1TableOffset = header.uint64(at: 40)

        if version == 3 {
            try Self.validateFeatures(header)
        }
        let clustersNeeded = (virtualSize + UInt64(1 << clusterBits) - 1) >> UInt64(clusterBits)
        let entriesPerL2 = UInt64(1 << (clusterBits - 3))
        guard UInt64(l1Size) * entriesPerL2 >= clustersNeeded else {
            throw QCOW2Error.corrupt("L1 table too small for the disk size")
        }
    }

    /// Rejects version-3 incompatible features this reader cannot handle safely.
    private static func validateFeatures(_ header: Data) throws {
        let incompatible = header.uint64(at: 72)
        if incompatible & (1 << 1) != 0 {
            throw QCOW2Error.corrupt("marked corrupt by its writer")
        }
        if incompatible & (1 << 2) != 0 {
            throw QCOW2Error.unsupportedFeature("external data file")
        }
        if incompatible & (1 << 4) != 0 {
            throw QCOW2Error.unsupportedFeature("extended L2 entries")
        }
        if incompatible & (1 << 3) != 0 {
            let headerLength = header.uint32(at: 100)
            if headerLength > 104, header.count > 104, header[header.startIndex + 104] != 0 {
                throw QCOW2Error.unsupportedFeature("zstd compression")
            }
        }
    }

    /// Writes the guest-visible disk as a sparse raw file. Unallocated and zero clusters are skipped,
    /// so they take no space on APFS.
    public func convertToRaw(at destination: URL) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.truncate(atOffset: virtualSize)

        let entriesPerL2 = clusterSize / 8
        let l1 = try Self.read(input, at: l1TableOffset, count: Int(l1Size) * 8)
        for l1Index in 0 ..< Int(l1Size) {
            let l2Offset = l1.uint64(at: l1Index * 8) & Self.offsetMask
            guard l2Offset != 0 else { continue } // whole L2 range unallocated → zeros
            let l2 = try Self.read(input, at: l2Offset, count: clusterSize)
            for l2Index in 0 ..< entriesPerL2 {
                let guestCluster = UInt64(l1Index * entriesPerL2 + l2Index)
                let guestOffset = guestCluster << UInt64(clusterBits)
                guard guestOffset < virtualSize else { return }
                let entry = l2.uint64(at: l2Index * 8)
                guard let data = try clusterData(entry, input: input) else { continue }
                let length = Int(min(UInt64(data.count), virtualSize - guestOffset))
                try output.seek(toOffset: guestOffset)
                try output.write(contentsOf: data.prefix(length))
            }
        }
    }

    /// The bytes of one guest cluster, or `nil` when it reads as zeros.
    func clusterData(_ entry: UInt64, input: FileHandle) throws -> Data? {
        if entry & Self.compressedFlag != 0 {
            return try compressedCluster(entry, input: input)
        }
        if version == 3, entry & 1 != 0 {
            return nil
        } // explicit zero cluster
        let hostOffset = entry & Self.offsetMask
        guard hostOffset != 0 else { return nil } // unallocated
        let data = try Self.read(input, at: hostOffset, count: clusterSize)
        guard data.count == clusterSize else { throw QCOW2Error.corrupt("cluster at \(hostOffset) is truncated") }
        return data.allSatisfy { $0 == 0 } ? nil : data
    }

    /// Compressed cluster descriptor: host offset in the low bits, sector count above it (spec §L2).
    private func compressedCluster(_ entry: UInt64, input: FileHandle) throws -> Data {
        let offsetBits = 62 - (UInt64(clusterBits) - 8)
        let hostOffset = entry & ((1 << offsetBits) - 1)
        let sectors = ((entry >> offsetBits) & ((1 << (UInt64(clusterBits) - 8)) - 1)) + 1
        let compressedLength = Int(sectors * 512 - (hostOffset & 511))
        let compressed = try Self.read(input, at: hostOffset, count: compressedLength)
        guard let cluster = Self.inflate(compressed, expectedSize: clusterSize) else {
            throw QCOW2Error.corrupt("compressed cluster at \(hostOffset) cannot be decoded")
        }
        return cluster
    }

    /// Raw DEFLATE (no zlib header), which is exactly what `COMPRESSION_ZLIB` decodes.
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            data.withUnsafeBytes { source -> Int in
                guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                      let input = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(target, expectedSize, input, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        if written < expectedSize {
            output.resetBytes(in: written ..< expectedSize)
        }
        return output
    }

    static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }
}

extension Data {
    func uint32(at offset: Int) -> UInt32 {
        self[startIndex + offset ..< startIndex + offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    func uint64(at offset: Int) -> UInt64 {
        self[startIndex + offset ..< startIndex + offset + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
