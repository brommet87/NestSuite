// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// A number of bytes, stored as `UInt64`.
///
/// Memory and disk sizes are passed around as `ByteCount` instead of bare integers, so a value in
/// MiB can never be mistaken for a value in bytes.
public struct ByteCount: Hashable, Comparable, Codable, Sendable {
    public var bytes: UInt64

    public init(bytes: UInt64) {
        self.bytes = bytes
    }

    public static func mebibytes(_ value: UInt64) -> ByteCount {
        ByteCount(bytes: value * 1024 * 1024)
    }

    public static func gibibytes(_ value: UInt64) -> ByteCount {
        ByteCount(bytes: value * 1024 * 1024 * 1024)
    }

    /// The value in whole GiB, rounded down.
    public var wholeGibibytes: UInt64 {
        bytes / (1024 * 1024 * 1024)
    }

    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool {
        lhs.bytes < rhs.bytes
    }

    /// Encode as a plain number so config files stay human-readable.
    public init(from decoder: any Decoder) throws {
        bytes = try decoder.singleValueContainer().decode(UInt64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }
}

extension ByteCount: CustomStringConvertible {
    /// A localized, human-readable size such as "8 GB", formatted as memory.
    public var description: String {
        bytes.formatted(.byteCount(style: .memory))
    }
}
