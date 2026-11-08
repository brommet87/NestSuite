// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import Testing
@testable import NestVirtualization

@Suite("HostCapabilities.current")
struct HostCapabilitiesCurrentTests {
    @Test("reports plausible values for the build machine")
    func plausibleValues() {
        let host = HostCapabilities.current()
        #expect(host.cpuCount >= 1)
        #expect(host.minimumCPUCount >= 1)
        #expect(host.maximumCPUCount >= host.minimumCPUCount)
        #expect(host.physicalMemory > .zero)
        #expect(host.maximumMemorySize >= host.minimumMemorySize)
        #expect(host.recommendedMaximumMemory <= host.maximumMemorySize)
    }
}

private extension ByteCount {
    static let zero = ByteCount(bytes: 0)
}
