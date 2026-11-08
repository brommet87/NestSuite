// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Compression
import Foundation
import Testing
@testable import NestImages

/// Builds small qcow2 images by hand from the format specification, so the reader is tested against
/// the spec rather than against itself.
struct QCOW2Builder {
    var version: UInt32 = 3
    let clusterBits: UInt32 = 12 // 4 KiB clusters keep fixtures small
    var virtualClusters = 8
    var incompatibleFeatures: UInt64 = 0
    var backingFileOffset: UInt64 = 0
    var encryption: UInt32 = 0

    enum Cluster {
        case data(UInt8)
        case compressed(UInt8)
        case zeroFlag
        case unallocated
    }

    var clusterSize: Int {
        1 << Int(clusterBits)
    }

    func build(_ clusters: [Cluster]) -> Data {
        // Layout: 0 header · 1 L1 · 2 L2 · 3… data clusters
        var file = Data(count: clusterSize * 3)
        func put64(_ value: UInt64, at offset: Int, in data: inout Data) {
            for index in 0 ..< 8 {
                data[offset + index] = UInt8(value >> (56 - 8 * UInt64(index)) & 0xFF)
            }
        }
        func put32(_ value: UInt32, at offset: Int, in data: inout Data) {
            for index in 0 ..< 4 {
                data[offset + index] = UInt8(value >> (24 - 8 * UInt32(index)) & 0xFF)
            }
        }
        put32(QCOW2Image.magic, at: 0, in: &file)
        put32(version, at: 4, in: &file)
        put64(backingFileOffset, at: 8, in: &file)
        put32(clusterBits, at: 20, in: &file)
        put64(UInt64(virtualClusters * clusterSize), at: 24, in: &file)
        put32(encryption, at: 32, in: &file)
        // One L1 entry covers clusterSize / 8 clusters; only the first L2 table is populated.
        let l1Size = (virtualClusters + clusterSize / 8 - 1) / (clusterSize / 8)
        put32(UInt32(l1Size), at: 36, in: &file) // L1 size
        put64(UInt64(clusterSize), at: 40, in: &file) // L1 offset
        if version == 3 {
            put64(incompatibleFeatures, at: 72, in: &file)
            put32(112, at: 100, in: &file) // header length
        }
        put64(UInt64(clusterSize * 2), at: clusterSize, in: &file) // L1[0] → L2

        for (index, cluster) in clusters.enumerated() {
            let entryOffset = clusterSize * 2 + index * 8
            switch cluster {
            case let .data(byte):
                put64(UInt64(file.count), at: entryOffset, in: &file)
                file.append(Data(repeating: byte, count: clusterSize))
            case let .compressed(byte):
                let compressed = Self.deflate(Data(repeating: byte, count: clusterSize))
                let hostOffset = UInt64(file.count)
                let offsetBits = 62 - (UInt64(clusterBits) - 8)
                let sectors = UInt64((compressed.count + 511) / 512)
                put64(QCOW2Image.compressedFlag | (sectors - 1) << offsetBits | hostOffset, at: entryOffset, in: &file)
                file.append(compressed)
                file.append(Data(count: Int(sectors) * 512 - compressed.count))
            case .zeroFlag:
                put64(1, at: entryOffset, in: &file)
            case .unallocated:
                break
            }
        }
        return file
    }

    static func deflate(_ data: Data) -> Data {
        var output = Data(count: data.count + 1024)
        let size = output.withUnsafeMutableBytes { destination -> Int in
            data.withUnsafeBytes { source -> Int in
                guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                      let input = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_encode_buffer(target, data.count + 1024, input, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return output.prefix(size)
    }
}

@Suite("qcow2 reader")
struct QCOW2Tests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "QCOW2Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func convert(_ data: Data) throws -> Data {
        let source = directory.appending(path: "image.qcow2")
        let target = directory.appending(path: "disk.raw")
        try data.write(to: source)
        try QCOW2Image(url: source).convertToRaw(at: target)
        return try Data(contentsOf: target)
    }

    @Test(
        "standard, compressed, zero and unallocated clusters map to the right guest offsets",
        arguments: [2, 3] as [UInt32]
    )
    func mixedClusters(version: UInt32) throws {
        var builder = QCOW2Builder()
        builder.version = version
        let raw = try convert(builder.build([.data(0xAA), .unallocated, .compressed(0x5C), .zeroFlag, .data(0x01)]))
        let size = builder.clusterSize
        #expect(raw.count == builder.virtualClusters * size)
        #expect(raw[0 ..< size].allSatisfy { $0 == 0xAA })
        #expect(raw[size ..< 2 * size].allSatisfy { $0 == 0 })
        #expect(raw[2 * size ..< 3 * size].allSatisfy { $0 == 0x5C })
        #expect(raw[4 * size ..< 5 * size].allSatisfy { $0 == 0x01 })
        #expect(raw[(5 * size)...].allSatisfy { $0 == 0 })
    }

    @Test("the raw disk is sparse: unallocated clusters take no space")
    func sparse() throws {
        var builder = QCOW2Builder()
        // 64 MiB disk with one data cluster. (APFS stores files up to ~16 MiB densely regardless of
        // holes, so smaller fixtures can't show sparseness.)
        builder.virtualClusters = 16384
        _ = try convert(builder.build([.data(0x42)]))
        let values = try directory.appending(path: "disk.raw")
            .resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        #expect(values.fileSize == 64 * 1024 * 1024)
        #expect((values.totalFileAllocatedSize ?? .max) < 1024 * 1024)
    }

    @Test("files that are not qcow2 are rejected")
    func notQCOW2() throws {
        let source = directory.appending(path: "plain.raw")
        try Data(repeating: 0, count: 4096).write(to: source)
        #expect(throws: QCOW2Image.QCOW2Error.notQCOW2) { try QCOW2Image(url: source) }
    }

    @Test("unsupported features are refused with a clear reason")
    func unsupported() throws {
        func open(_ builder: QCOW2Builder) throws {
            let source = directory.appending(path: "x.qcow2")
            try builder.build([]).write(to: source)
            _ = try QCOW2Image(url: source)
        }
        var backing = QCOW2Builder()
        backing.backingFileOffset = 512
        #expect(throws: QCOW2Image.QCOW2Error.unsupportedFeature("backing file")) { try open(backing) }

        var encrypted = QCOW2Builder()
        encrypted.encryption = 1
        #expect(throws: QCOW2Image.QCOW2Error.unsupportedFeature("encryption")) { try open(encrypted) }

        var extended = QCOW2Builder()
        extended.incompatibleFeatures = 1 << 4
        #expect(throws: QCOW2Image.QCOW2Error.unsupportedFeature("extended L2 entries")) { try open(extended) }

        var corrupt = QCOW2Builder()
        corrupt.incompatibleFeatures = 1 << 1
        #expect(throws: QCOW2Image.QCOW2Error.self) { try open(corrupt) }
    }
}
