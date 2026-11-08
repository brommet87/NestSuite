// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

extension HostCapabilities {
    /// A typical 12-core, 32 GB Apple silicon Mac.
    static let fixture = HostCapabilities(
        cpuCount: 12,
        physicalMemory: .gibibytes(32),
        minimumCPUCount: 1,
        maximumCPUCount: 12,
        minimumMemorySize: .mebibytes(128),
        maximumMemorySize: .gibibytes(32),
        isRosettaAvailable: true,
        supportsMacOSGuests: true
    )
}

extension VirtualMachineConfiguration {
    static func fixture(
        guest: GuestOperatingSystem = .linux,
        name: String = "Ubuntu",
        cpuCount: Int = 4,
        memorySize: ByteCount = .gibibytes(8),
        diskSize: ByteCount = .gibibytes(32)
    ) -> VirtualMachineConfiguration {
        VirtualMachineConfiguration(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            name: name,
            guest: guest,
            cpuCount: cpuCount,
            memorySize: memorySize,
            diskSize: diskSize,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

/// A fresh temporary directory that is removed when the value goes out of scope.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "NestCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
