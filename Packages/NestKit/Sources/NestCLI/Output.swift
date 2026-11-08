// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Foundation
import NestCore
import NestSpec

/// Exit codes follow BSD `sysexits(3)`, so scripts and CI can react to the kind of failure.
/// Documented in `docs/cli.md`; changing a value is a breaking change.
public enum NestExitCode {
    public static let success = ExitCode.success // 0
    public static let failure = ExitCode.failure // 1  unexpected error
    public static let usage = ExitCode(64) // EX_USAGE    wrong arguments (ArgumentParser)
    public static let invalidInput = ExitCode(65) // EX_DATAERR  Nestfile or configuration invalid
    public static let notFound = ExitCode(66) // EX_NOINPUT  machine or file not found
    public static let cannotCreate = ExitCode(73) // EX_CANTCREAT target exists / cannot be written
}

/// Where command output goes. Abstracted so tests can capture it.
public protocol OutputSink: AnyObject, Sendable {
    func write(_ text: String)
    func writeError(_ text: String)
}

public final class StandardOutput: OutputSink, @unchecked Sendable {
    // @unchecked: FileHandle writes are thread-safe; the class has no mutable state.
    public init() {}

    public func write(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    public func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Renders results either as aligned text for humans or as stable JSON for scripts.
struct Renderer {
    let json: Bool
    let sink: any OutputSink

    func emit(_ value: some Encodable, human: () -> String) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try sink.write(String(bytes: encoder.encode(value), encoding: .utf8) ?? "")
        } else {
            sink.write(human())
        }
    }

    /// Errors go to stderr in human mode and as `{"error": …}` on stdout in JSON mode, so a script
    /// always receives parseable output.
    func fail(_ message: String, code: ExitCode) -> ExitCode {
        if json {
            try? emit(ErrorDTO(error: message, exitCode: code.rawValue)) { "" }
        } else {
            sink.writeError("error: \(message)")
        }
        return code
    }
}

struct ErrorDTO: Encodable {
    let error: String
    let exitCode: Int32
}

/// Formats rows as a left-aligned table with a header, like `docker ps`.
func table(header: [String], rows: [[String]]) -> String {
    let all = [header] + rows
    let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
    return all.map { row in
        row.enumerated()
            .map { index, cell in index == row.count - 1 ? cell : cell.padding(
                toLength: widths[index],
                withPad: " ",
                startingAt: 0
            ) }
            .joined(separator: "  ")
    }
    .joined(separator: "\n")
}
