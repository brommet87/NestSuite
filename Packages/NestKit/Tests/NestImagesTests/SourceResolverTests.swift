// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestImages

/// Serves canned responses so resolution can be tested without the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    // @unchecked: `responses` is written once per test before any request is made.
    nonisolated(unsafe) static var responses: [String: String] = [:]

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: Self.responses[url.absoluteString] == nil ? 404 : 200,
                  httpVersion: nil,
                  headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body = Self.responses[url.absoluteString]
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session(_ responses: [String: String]) -> URLSession {
        self.responses = responses
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("Source resolution", .serialized)
struct SourceResolverTests {
    let hash = String(repeating: "12", count: 32)

    @Test("a checksum list picks the highest matching version")
    func checksumList() async throws {
        let session = StubProtocol.session([
            "https://example.org/rel/SHA256SUMS": "\(hash)  distro-1.9.iso\n\(hash.uppercased())  distro-1.10.iso\n\(hash)  other.iso",
        ])
        let resolved = try await SourceResolver(session: session).resolve(.checksumList(
            #require(URL(string: "https://example.org/rel/SHA256SUMS")), file: #"distro-1\.\d+\.iso"#
        ))
        #expect(try resolved == ResolvedImage(
            fileURL: #require(URL(string: "https://example.org/rel/distro-1.10.iso")),
            checksum: hash
        ))
    }

    @Test("an indexed checksum list is found in the folder first")
    func indexedChecksumList() async throws {
        let session = StubProtocol.session([
            "https://example.org/images/": #"<a href="?C=N">x</a><a href="Distro-44-1.6-CHECKSUM">a</a><a href="Distro-44-1.7-CHECKSUM">b</a>"#,
            "https://example.org/images/Distro-44-1.7-CHECKSUM": "SHA256 (Distro-44-1.7.qcow2) = \(hash)",
        ])
        let resolved = try await SourceResolver(session: session).resolve(.indexedChecksumList(
            index: #require(URL(string: "https://example.org/images/")), list: #"Distro-44-.*-CHECKSUM"#,
            file: #"Distro-44-.*\.qcow2"#
        ))
        #expect(resolved.fileURL.lastPathComponent == "Distro-44-1.7.qcow2")
    }

    @Test("a fixed file uses the checksum file next to it, including bare-hash files")
    func fileWithChecksum() async throws {
        let session = StubProtocol.session(["https://example.org/a/disk.qcow2.sha256": hash])
        let resolved = try await SourceResolver(session: session).resolve(.fileWithChecksum(
            #require(URL(string: "https://example.org/a/disk.qcow2")), checksumSuffix: ".sha256"
        ))
        #expect(resolved.checksum == hash)
    }

    @Test("an indexed file takes the newest version from the folder")
    func indexedFile() async throws {
        let session = StubProtocol.session([
            "https://example.org/cloud/": #"<a href="img-3.24.9.tar.gz">"<a href="img-3.24.10.tar.gz">"<a href="img-3.24.10.tar.gz.sha512">"#,
            "https://example.org/cloud/img-3.24.10.tar.gz.sha512": "\(String(repeating: "ef", count: 64))  img-3.24.10.tar.gz",
        ])
        let resolved = try await SourceResolver(session: session).resolve(.indexedFile(
            index: #require(URL(string: "https://example.org/cloud/")), file: #"img-3\.24\.\d+\.tar\.gz"#,
            checksumSuffix: ".sha512"
        ))
        #expect(resolved.fileURL.lastPathComponent == "img-3.24.10.tar.gz")
        #expect(resolved.checksum.count == 128)
    }

    @Test("a latest-pointer file names the current build")
    func latestPointer() async throws {
        let session = StubProtocol.session([
            "https://example.org/auto/latest-iso.txt": "# Latest\n20261101/install-minimal-20261101.iso 123\n",
            "https://example.org/auto/20261101/install-minimal-20261101.iso.sha256": "\(hash)  install-minimal-20261101.iso",
        ])
        let resolved = try await SourceResolver(session: session).resolve(.latestPointer(
            #require(URL(string: "https://example.org/auto/latest-iso.txt")), file: #".*install-minimal.*\.iso"#,
            checksumSuffix: ".sha256"
        ))
        #expect(resolved.fileURL.absoluteString == "https://example.org/auto/20261101/install-minimal-20261101.iso")
    }

    @Test("a missing file is reported, not guessed")
    func missing() async throws {
        let session = StubProtocol.session(["https://example.org/SUMS": "\(hash)  something-else.iso"])
        await #expect(throws: ImageError.self) {
            try await SourceResolver(session: session).resolve(.checksumList(
                #require(URL(string: "https://example.org/SUMS")), file: #"wanted\.iso"#
            ))
        }
    }

    @Test("natural order compares numbers numerically")
    func naturalOrder() {
        #expect(SourceResolver.naturalOrder("3.24.9", "3.24.10"))
        #expect(!SourceResolver.naturalOrder("10", "9"))
    }
}
