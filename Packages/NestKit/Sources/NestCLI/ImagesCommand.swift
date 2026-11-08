// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import ArgumentParser
import Foundation
import NestCore
import NestImages

/// `nestctl images` — the image catalog and what is cached locally.
struct Images: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List catalog images and show which are downloaded.",
        discussion: """
        Cloud images boot directly and are set up by cloud-init (use them as `image:` in a Nestfile). \
        Installers are ISOs for `nestctl run <machine> --iso <image>`. Everything comes from the \
        distributions’ own servers and is verified against their published checksums.
        """
    )

    @OptionGroup var options: GlobalOptions
    @Option(help: "Images folder (default: the NestSuite app’s).", completion: .directory) var images: String?

    struct ImageDTO: Encodable, Equatable {
        let id: String
        let kind: String
        let family: String
        let aliases: [String]
        let name: String
        let downloadBytes: UInt64
        let cached: Bool
        let source: String
    }

    func run() throws {
        let store = ImageStore(rootURL: images.map { URL(filePath: ($0 as NSString).expandingTildeInPath) }
            ?? ImageStore.appImagesURL())
        let rows = ImageCatalog.all.map { image in
            ImageDTO(
                id: image.id, kind: image.kind.rawValue, family: image.family, aliases: image.aliases,
                name: image.displayName,
                downloadBytes: image.downloadSize.bytes, cached: store.cachedImage(for: image) != nil,
                source: image.sourceHost
            )
        }
        try Renderer(json: options.json, sink: Environment.current.sink).emit(rows) {
            table(
                header: ["IMAGE", "KIND", "NAME", "DOWNLOAD", "CACHED", "SOURCE"],
                rows: rows.map {
                    [
                        $0.id, $0.kind, $0.name, "≈ " + ByteCount(bytes: $0.downloadBytes).description,
                        $0.cached ? "yes" : "no", $0.source,
                    ]
                }
            )
        }
    }
}
