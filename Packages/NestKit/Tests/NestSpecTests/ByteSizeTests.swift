// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import Testing
@testable import NestSpec

@Suite("ByteSize")
struct ByteSizeTests {
    @Test("binary units and shorthands", arguments: [
        ("8GiB", ByteCount.gibibytes(8)),
        ("8G", .gibibytes(8)),
        ("8 GiB", .gibibytes(8)),
        ("512MiB", .mebibytes(512)),
        ("512m", .mebibytes(512)),
        ("1.5GiB", .mebibytes(1536)),
        ("1TiB", .gibibytes(1024)),
        ("4096b", ByteCount(bytes: 4096)),
    ])
    func parses(text: String, expected: ByteCount) throws {
        #expect(try ByteSize.parse(text) == expected)
    }

    @Test("decimal-looking units are rejected with a suggestion")
    func ambiguous() {
        #expect(throws: ByteSize.ParseError.ambiguousUnit("8GB", suggestion: "8GiB")) { try ByteSize.parse("8GB") }
    }

    @Test("missing, unknown and invalid input", arguments: [
        ("", ByteSize.ParseError.empty),
        ("8", .missingUnit("8")),
        ("8 parsecs", .unknownUnit("parsecs")),
        ("GiB", .invalidNumber("")),
        ("0GiB", .invalidNumber("0")),
    ])
    func rejects(text: String, error: ByteSize.ParseError) {
        #expect(throws: error) { try ByteSize.parse(text) }
    }

    @Test("errors read well")
    func messages() {
        #expect(ByteSize.ParseError.missingUnit("8").description == "“8” has no unit; write e.g. “8GiB”")
    }
}
