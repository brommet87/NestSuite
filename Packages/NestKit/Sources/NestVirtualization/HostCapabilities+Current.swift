// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Virtualization

public extension HostCapabilities {
    /// The capabilities of the Mac this process is running on, as reported by
    /// `Virtualization.framework`.
    static func current(processInfo: ProcessInfo = .processInfo) -> HostCapabilities {
        HostCapabilities(
            cpuCount: processInfo.processorCount,
            physicalMemory: ByteCount(bytes: processInfo.physicalMemory),
            minimumCPUCount: VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            maximumCPUCount: VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            minimumMemorySize: ByteCount(bytes: VZVirtualMachineConfiguration.minimumAllowedMemorySize),
            maximumMemorySize: ByteCount(bytes: VZVirtualMachineConfiguration.maximumAllowedMemorySize),
            isRosettaAvailable: isRosettaAvailable,
            supportsMacOSGuests: isAppleSilicon
        )
    }

    /// Rosetta for Linux exists only on Apple silicon; the API is absent from Intel builds.
    private static var isRosettaAvailable: Bool {
        #if arch(arm64)
            VZLinuxRosettaDirectoryShare.availability != .notSupported
        #else
            false
        #endif
    }

    /// macOS guests require Apple silicon.
    private static var isAppleSilicon: Bool {
        #if arch(arm64)
            true
        #else
            false
        #endif
    }
}
