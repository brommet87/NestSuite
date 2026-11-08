// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// The concrete file to download for a catalog entry, with the checksum its distribution publishes.
public struct ResolvedImage: Equatable, Sendable {
    public let fileURL: URL
    /// Lowercase hex; 64 digits for SHA-256, 128 for SHA-512.
    public let checksum: String
}

/// Turns a ``CatalogImage/Source`` into a file URL and checksum by reading the distribution’s
/// checksum lists and folder indexes. Versioned file names are matched by pattern; when several match,
/// the highest version wins (natural sort, so `3.24.10` beats `3.24.9`).
struct SourceResolver: Sendable {
    let session: URLSession

    func resolve(_ source: CatalogImage.Source) async throws -> ResolvedImage {
        switch source {
        case let .checksumList(listURL, pattern):
            return try await fromChecksumList(listURL, pattern: pattern)

        case let .indexedChecksumList(index, listPattern, pattern):
            let list = try await newest(in: index, matching: listPattern)
            return try await fromChecksumList(index.appending(path: list), pattern: pattern)

        case let .fileWithChecksum(fileURL, suffix):
            return try await ResolvedImage(fileURL: fileURL, checksum: checksum(next: fileURL, suffix: suffix))

        case let .indexedFile(index, pattern, suffix):
            let file = try await index.appending(path: newest(in: index, matching: pattern))
            return try await ResolvedImage(fileURL: file, checksum: checksum(next: file, suffix: suffix))

        case let .latestPointer(pointerURL, pattern, suffix):
            let text = try await fetchText(pointerURL)
            let regex = try Regex(pattern)
            guard let path = text.split(whereSeparator: \.isNewline)
                .lazy
                .filter({ !$0.hasPrefix("#") })
                .compactMap({ $0.split(separator: " ").first.map(String.init) })
                .first(where: { $0.wholeMatch(of: regex) != nil })
            else { throw ImageError.resolutionFailed("no build listed in \(pointerURL.lastPathComponent)") }
            let file = pointerURL.deletingLastPathComponent().appending(path: path)
            return try await ResolvedImage(fileURL: file, checksum: checksum(next: file, suffix: suffix))
        }
    }

    // MARK: - Strategies

    private func fromChecksumList(_ listURL: URL, pattern: String) async throws -> ResolvedImage {
        let sums = try await ChecksumFile.parse(fetchText(listURL))
        let regex = try Regex(pattern)
        guard let name = sums.keys.filter({ $0.wholeMatch(of: regex) != nil }).max(by: Self.naturalOrder) else {
            throw ImageError.resolutionFailed("no file matching the catalog entry in \(listURL.lastPathComponent)")
        }
        return ResolvedImage(
            fileURL: listURL.deletingLastPathComponent().appending(path: name),
            checksum: sums[name] ?? ""
        )
    }

    private func checksum(next file: URL, suffix: String) async throws -> String {
        let checksumURL = file.deletingLastPathComponent().appending(path: file.lastPathComponent + suffix)
        let sums = try await ChecksumFile.parse(fetchText(checksumURL))
        guard let hash = sums[file.lastPathComponent] ?? sums[""] ?? (sums.count == 1 ? sums.values.first : nil) else {
            throw ImageError.checksumMissing(file: file.lastPathComponent)
        }
        return hash
    }

    private func newest(in index: URL, matching pattern: String) async throws -> String {
        let names = try await Self.links(in: fetchText(index))
        let regex = try Regex(pattern)
        guard let newest = names.filter({ $0.wholeMatch(of: regex) != nil }).max(by: Self.naturalOrder) else {
            throw ImageError.resolutionFailed("no matching file in \(index.absoluteString)")
        }
        return newest
    }

    private func fetchText(_ url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ImageError.resolutionFailed("HTTP \(status) for \(url.absoluteString)")
        }
        return data.lossyUTF8
    }

    // MARK: - Parsing helpers

    /// File names linked from an HTML folder index (`href="name"`), without query strings or folders.
    static func links(in html: String) -> [String] {
        html.matches(of: /href="([^"?\/]+)"/).map { String($0.output.1) }
    }

    /// Natural ordering: digit runs compare numerically.
    static func naturalOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric]) == .orderedAscending
    }
}
