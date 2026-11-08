// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

/// Creates a ready-to-boot machine from a catalog image: bundle, disk cloned from the verified base
/// image, and the cloud-init seed. Used by `nestctl up` and the app.
public struct MachineProvisioner: Sendable {
    public let library: VirtualMachineLibrary
    public let store: ImageStore

    public init(library: VirtualMachineLibrary, store: ImageStore) {
        self.library = library
        self.store = store
    }

    public func provision(
        _ configuration: VirtualMachineConfiguration,
        from image: CatalogImage,
        seed: CloudInitSeed,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> VirtualMachineBundle {
        let base = try await store.fetch(image, progress: progress)
        var configuration = configuration
        let baseSize = try UInt64(base.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        configuration.diskSize = max(configuration.diskSize, image.minimumDiskSize, ByteCount(bytes: baseSize))

        let bundle = try library.createBundle(for: configuration)
        do {
            try DiskProvisioner.createDisk(from: base, at: bundle.diskImageURL, size: configuration.diskSize)
            try seed.volume().write(to: bundle.cloudInitSeedURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: bundle.url) // never leave half-provisioned machines
            throw error
        }
        return bundle
    }

    /// Reads `NESTSUITE-READY …` from the console log, if the guest has reported in.
    public static func readyReport(in consoleLog: URL) -> String? {
        guard let data = try? Data(contentsOf: consoleLog) else { return nil }
        let text = data.lossyUTF8
        return text.split(whereSeparator: \.isNewline)
            .last { $0.contains(CloudInitSeed.readyMarker) }
            .map { line in
                let start = line.range(of: CloudInitSeed.readyMarker)?.upperBound ?? line.startIndex
                return line[start...].trimmingCharacters(in: .whitespaces)
            }
    }
}
