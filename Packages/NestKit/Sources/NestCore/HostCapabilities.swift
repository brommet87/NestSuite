// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

/// What the Mac running NestSuite can offer to virtual machines.
///
/// `NestCore` never asks the system directly. `NestVirtualization` fills this in from
/// `Virtualization.framework` and `ProcessInfo`, and tests pass fixed values. This keeps validation
/// deterministic and testable.
public struct HostCapabilities: Hashable, Sendable {
    public var cpuCount: Int
    public var physicalMemory: ByteCount
    public var minimumCPUCount: Int
    public var maximumCPUCount: Int
    public var minimumMemorySize: ByteCount
    public var maximumMemorySize: ByteCount
    public var isRosettaAvailable: Bool
    public var supportsMacOSGuests: Bool

    public init(
        cpuCount: Int,
        physicalMemory: ByteCount,
        minimumCPUCount: Int,
        maximumCPUCount: Int,
        minimumMemorySize: ByteCount,
        maximumMemorySize: ByteCount,
        isRosettaAvailable: Bool,
        supportsMacOSGuests: Bool
    ) {
        self.cpuCount = cpuCount
        self.physicalMemory = physicalMemory
        self.minimumCPUCount = minimumCPUCount
        self.maximumCPUCount = maximumCPUCount
        self.minimumMemorySize = minimumMemorySize
        self.maximumMemorySize = maximumMemorySize
        self.isRosettaAvailable = isRosettaAvailable
        self.supportsMacOSGuests = supportsMacOSGuests
    }

    /// Memory macOS should keep for itself so the host stays responsive.
    public static let hostMemoryReserve = ByteCount.gibibytes(4)

    /// The largest memory size we recommend giving one VM: physical memory minus the host reserve,
    /// never above the framework maximum.
    public var recommendedMaximumMemory: ByteCount {
        let available = physicalMemory.bytes > Self.hostMemoryReserve.bytes
            ? physicalMemory.bytes - Self.hostMemoryReserve.bytes
            : minimumMemorySize.bytes
        return min(ByteCount(bytes: available), maximumMemorySize)
    }
}
