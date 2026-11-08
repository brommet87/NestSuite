// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import CryptoKit
import Foundation
import NestCore

public enum ImageError: Error, Equatable, Sendable {
    case unknownImage(String)
    case checksumMissing(file: String)
    case checksumMismatch(expected: String, actual: String)
    case downloadFailed(String)
    case extractionFailed(String)
    case rawImageNotFound
    case conversionFailed(String)
    case resolutionFailed(String)
    case notBootable
}

extension ImageError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unknownImage(name):
            "unknown image “\(name)”; available: \(ImageCatalog.all.map(\.id).joined(separator: ", "))"
        case let .checksumMissing(file): "the distribution’s checksum list has no entry for \(file)"
        case let .checksumMismatch(expected, actual):
            "the download is corrupt or was tampered with (expected \(expected.prefix(16))…, got \(actual.prefix(16))…)"
        case let .downloadFailed(reason): "download failed: \(reason)"
        case let .extractionFailed(reason): "the archive could not be unpacked: \(reason)"
        case .rawImageNotFound: "the archive contains no disk image"
        case let .conversionFailed(reason): "the image could not be converted: \(reason)"
        case let .resolutionFailed(reason):
            "the current image could not be found on the distribution’s server: \(reason)"
        case .notBootable: "the downloaded image is not a bootable disk (no partition table)"
        }
    }
}

/// Progress of an image download, for progress bars.
public struct DownloadProgress: Sendable {
    public let receivedBytes: Int64
    public let totalBytes: Int64?

    public var fractionCompleted: Double? {
        totalBytes.map { $0 > 0 ? Double(receivedBytes) / Double($0) : 0 }
    }
}

/// Downloads, verifies and caches base images. Cached images are content-addressed by the archive
/// checksum, so a new upstream release is fetched automatically and an existing one never twice.
///
/// ```
/// Images/
/// └── ubuntu-24.04/
///     └── 3f2a…e91c.raw     verified, unpacked base disk (machines get APFS clones of it)
/// ```
public struct ImageStore: Sendable {
    public let rootURL: URL
    private let session: URLSession

    public init(rootURL: URL, session: URLSession = .shared) {
        self.rootURL = rootURL
        self.session = session
    }

    /// `~/Library/Application Support/NestSuite/Images` (inside the container when sandboxed).
    public static func defaultRootURL(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "NestSuite/Images", directoryHint: .isDirectory)
    }

    /// The images folder used by the sandboxed app, seen from an unsandboxed process (`nestctl`).
    public static func appImagesURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(
            path: "Library/Containers/\(VirtualMachineLibrary.appBundleIdentifier)/Data"
                + "/Library/Application Support/NestSuite/Images",
            directoryHint: .isDirectory
        )
    }

    func directory(for image: CatalogImage) -> URL {
        rootURL.appending(path: image.id, directoryHint: .isDirectory)
    }

    /// The file extension of a prepared image: raw disks for cloud images, ISOs for installers.
    static func preparedExtension(for image: CatalogImage) -> String {
        image.format == .iso ? "iso" : "raw"
    }

    /// The newest verified local copy, if any (no network access).
    public func cachedImage(for image: CatalogImage, fileManager: FileManager = .default) -> URL? {
        let folder = directory(for: image)
        let files = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files
            .filter { $0.pathExtension == Self.preparedExtension(for: image) }
            .max { modified($0) < modified($1) }
    }

    /// Returns a verified, ready-to-use image (raw disk or ISO), downloading it when the published
    /// checksum changed or nothing is cached.
    public func fetch(
        _ image: CatalogImage,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let resolved = try await SourceResolver(session: session).resolve(image.source)
        let folder = directory(for: image)
        let target = folder.appending(path: "\(resolved.checksum.prefix(32)).\(Self.preparedExtension(for: image))")
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            return target
        }

        let work = rootURL.appending(path: ".download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let downloaded = work.appending(path: resolved.fileURL.lastPathComponent)
        try await download(resolved.fileURL, to: downloaded, progress: progress)

        let actual = try Self.hash(of: downloaded, matching: resolved.checksum)
        guard actual == resolved.checksum else {
            throw ImageError.checksumMismatch(expected: resolved.checksum, actual: actual)
        }

        let prepared: URL = switch image.format {
        case .iso: downloaded
        case .tarRaw: try Self.extractRawImage(from: downloaded, into: work)
        case .qcow2: try Self.convertQCOW2(downloaded, into: work)
        }
        if image.format != .iso, !Self.hasPartitionTable(prepared) {
            throw ImageError.notBootable
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: prepared, to: target)
        return target
    }

    /// A bootable disk starts with a partition table: GPT (`EFI PART` in sector 1) or an MBR
    /// signature. Bare file system images (as found in some archives) have neither.
    static func hasPartitionTable(_ disk: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: disk),
              let head = try? handle.read(upToCount: 1024), head.count == 1024
        else { return false }
        try? handle.close()
        let gpt = head[512 ..< 520].elementsEqual("EFI PART".utf8)
        let mbr = head[510] == 0x55 && head[511] == 0xAA
        return gpt || mbr
    }

    static func convertQCOW2(_ source: URL, into folder: URL) throws -> URL {
        let output = folder.appending(path: "disk.raw")
        do {
            try QCOW2Image(url: source).convertToRaw(at: output)
        } catch let error as QCOW2Image.QCOW2Error {
            throw ImageError.conversionFailed(error.description)
        }
        return output
    }

    private func download(
        _ url: URL,
        to destination: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        let (temporary, response) = try await session.download(from: url, delegate: ProgressDelegate(report: progress))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ImageError.downloadFailed("HTTP \(status) for \(url.lastPathComponent)")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    /// Streams the file through the hash so multi-gigabyte images never sit in memory.
    /// The algorithm follows the expected checksum: 64 hex digits = SHA-256, 128 = SHA-512.
    static func hash(of url: URL, matching expected: String) throws -> String {
        let useSHA512 = expected.count == 128
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha256 = SHA256()
        var sha512 = SHA512()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            if useSHA512 {
                sha512.update(data: chunk)
            } else {
                sha256.update(data: chunk)
            }
        }
        let digest: any Digest = useSHA512 ? sha512.finalize() : sha256.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks with the system `tar` (handles gzip and xz) and returns the raw disk image — the
    /// largest file in the archive (archives may also contain manifests or signatures).
    static func extractRawImage(from archive: URL, into folder: URL) throws -> URL {
        let output = folder.appending(path: "unpacked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path(percentEncoded: false), "-C", output.path(percentEncoded: false)]
        let errors = Pipe()
        tar.standardError = errors
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            let message = errors.fileHandleForReading.readDataToEndOfFile().lossyUTF8
            throw ImageError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let enumerator = FileManager.default.enumerator(at: output, includingPropertiesForKeys: [.fileSizeKey])
        var largest: (url: URL, size: Int)?
        while let url = enumerator?.nextObject() as? URL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > (largest?.size ?? 0) {
                largest = (url, size)
            }
        }
        guard let largest else { throw ImageError.rawImageNotFound }
        return largest.url
    }
}

/// Forwards download progress from the task delegate.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @Sendable (DownloadProgress) -> Void

    init(report: @escaping @Sendable (DownloadProgress) -> Void) {
        self.report = report
    }

    func urlSession(
        _: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        report(DownloadProgress(receivedBytes: totalBytesWritten, totalBytes: total))
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo _: URL) {
        // The async `download(from:delegate:)` API hands the file to the caller.
    }
}

/// Creates a machine disk from a base image: an APFS clone (instant, no extra space), grown to the
/// machine’s disk size. The guest grows its file system on first boot (cloud-init `growpart`).
public enum DiskProvisioner {
    public static func createDisk(from base: URL, at destination: URL, size: ByteCount) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: base, to: destination)
        let current = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if UInt64(current) < size.bytes {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.truncate(atOffset: size.bytes)
        }
    }
}
