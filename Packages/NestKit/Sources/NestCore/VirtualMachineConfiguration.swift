// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// Everything that describes a virtual machine, independent of how it is executed.
///
/// The configuration is persisted as `config.json` inside the VM bundle (see ``VirtualMachineBundle``).
/// It is a plain value type: editing a copy never affects a running machine until it is saved.
public struct VirtualMachineConfiguration: Identifiable, Hashable, Codable, Sendable {
    /// Bumped whenever the on-disk format changes incompatibly. Readers reject newer versions.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    public let guest: GuestOperatingSystem
    public var cpuCount: Int
    public var memorySize: ByteCount
    public var diskSize: ByteCount
    public var display: DisplayConfiguration
    public var network: NetworkMode
    public var sharedFolders: [SharedFolder]
    public var isClipboardSharingEnabled: Bool
    /// Only honored for Linux guests (see ``GuestOperatingSystem/supportsRosetta``).
    public var isRosettaEnabled: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        guest: GuestOperatingSystem,
        cpuCount: Int,
        memorySize: ByteCount,
        diskSize: ByteCount,
        display: DisplayConfiguration = .standard,
        network: NetworkMode = .nat,
        sharedFolders: [SharedFolder] = [],
        isClipboardSharingEnabled: Bool = true,
        isRosettaEnabled: Bool = false,
        createdAt: Date = .now
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.guest = guest
        self.cpuCount = cpuCount
        self.memorySize = memorySize
        self.diskSize = diskSize
        self.display = display
        self.network = network
        self.sharedFolders = sharedFolders
        self.isClipboardSharingEnabled = isClipboardSharingEnabled
        self.isRosettaEnabled = isRosettaEnabled && guest.supportsRosetta
        // Whole seconds: the value is stored as ISO 8601 and must round-trip exactly.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    }

    /// Sensible defaults for a new machine, scaled to the host.
    ///
    /// Uses half the host's cores and a quarter of its memory, clamped to the host limits, so a new
    /// VM never starves macOS.
    public static func recommended(
        for guest: GuestOperatingSystem,
        name: String,
        host: HostCapabilities
    ) -> VirtualMachineConfiguration {
        let cpus = min(max(host.cpuCount / 2, host.minimumCPUCount), host.maximumCPUCount)
        let preferredMemory = ByteCount(bytes: host.physicalMemory.bytes / 4)
        let floor = guest == .macOS ? ByteCount.gibibytes(4) : ByteCount.gibibytes(2)
        let memory = min(max(preferredMemory, floor, host.minimumMemorySize), host.maximumMemorySize)
        let disk: ByteCount = guest == .macOS ? .gibibytes(80) : .gibibytes(32)
        return VirtualMachineConfiguration(
            name: name,
            guest: guest,
            cpuCount: cpus,
            memorySize: memory,
            diskSize: disk,
            isRosettaEnabled: guest.supportsRosetta && host.isRosettaAvailable
        )
    }
}

/// The virtual display presented to the guest.
public struct DisplayConfiguration: Hashable, Codable, Sendable {
    public var widthInPixels: Int
    public var heightInPixels: Int
    public var pixelsPerInch: Int
    /// Resize the guest display when the window size changes (requires guest support).
    public var automaticallyReconfigures: Bool

    public init(widthInPixels: Int, heightInPixels: Int, pixelsPerInch: Int, automaticallyReconfigures: Bool = true) {
        self.widthInPixels = widthInPixels
        self.heightInPixels = heightInPixels
        self.pixelsPerInch = pixelsPerInch
        self.automaticallyReconfigures = automaticallyReconfigures
    }

    public static let standard = DisplayConfiguration(widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 144)
}

/// How the guest reaches the network.
public enum NetworkMode: String, Codable, CaseIterable, Sendable {
    /// Shared network: the guest reaches the outside world through the Mac (NAT).
    case nat
    /// No network device at all — for isolated, offline machines.
    case disconnected
}

/// A Mac folder made available inside the guest via virtiofs.
public struct SharedFolder: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// The tag/name the guest sees, e.g. `Home`.
    public var name: String
    /// A security-scoped bookmark to the Mac folder, so access survives app restarts in the sandbox.
    public var bookmark: Data
    public var isReadOnly: Bool

    public init(id: UUID = UUID(), name: String, bookmark: Data, isReadOnly: Bool = false) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.isReadOnly = isReadOnly
    }
}
