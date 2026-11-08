// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

/// Parses human-written sizes such as `8GiB`, `512MiB` or `8G`.
///
/// Units are binary on purpose (`G` = `GiB`, the common convention in developer tools). Decimal-looking units such as
/// `GB` are rejected with a hint instead of guessing, because "8 GB" of memory is ambiguous.
public enum ByteSize {
    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case missingUnit(String)
        case ambiguousUnit(String, suggestion: String)
        case unknownUnit(String)
        case invalidNumber(String)
        case tooLarge(String)
    }

    private static let multipliers: [String: UInt64] = [
        "b": 1,
        "k": 1 << 10, "kib": 1 << 10,
        "m": 1 << 20, "mib": 1 << 20,
        "g": 1 << 30, "gib": 1 << 30,
        "t": 1 << 40, "tib": 1 << 40,
    ]

    private static let decimalUnits: [String: String] = ["kb": "KiB", "mb": "MiB", "gb": "GiB", "tb": "TiB"]

    public static func parse(_ text: String) throws(ParseError) -> ByteCount {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw .empty }

        let numberPart = trimmed.prefix { $0.isNumber || $0 == "." }
        let unitPart = trimmed.dropFirst(numberPart.count).trimmingCharacters(in: .whitespaces)

        guard !unitPart.isEmpty else { throw .missingUnit(trimmed) }
        let unit = unitPart.lowercased()
        if let suggestion = decimalUnits[unit] {
            throw .ambiguousUnit(trimmed, suggestion: "\(numberPart)\(suggestion)")
        }
        guard let multiplier = multipliers[unit] else { throw .unknownUnit(unitPart) }
        guard let value = Decimal(string: String(numberPart), locale: Locale(identifier: "en_US_POSIX")),
              value > 0
        else { throw .invalidNumber(String(numberPart)) }

        let bytes = value * Decimal(multiplier)
        guard bytes <= Decimal(UInt64.max) else { throw .tooLarge(trimmed) }
        return ByteCount(bytes: NSDecimalNumber(decimal: bytes).uint64Value)
    }
}

extension ByteSize.ParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty: "is empty"
        case let .missingUnit(text): "“\(text)” has no unit; write e.g. “\(text)GiB”"
        case let .ambiguousUnit(text, suggestion): "“\(text)” is ambiguous; write “\(suggestion)”"
        case let .unknownUnit(unit): "unknown unit “\(unit)”; use KiB, MiB, GiB or TiB"
        case let .invalidNumber(number): "“\(number)” is not a positive number"
        case let .tooLarge(text): "“\(text)” is too large"
        }
    }
}
