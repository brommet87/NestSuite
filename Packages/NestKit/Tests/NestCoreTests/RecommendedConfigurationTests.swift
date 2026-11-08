// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Testing
@testable import NestCore

@Suite("Recommended configuration")
struct RecommendedConfigurationTests {
    @Test("uses half the cores and a quarter of the memory")
    func scalesWithHost() {
        let config = VirtualMachineConfiguration.recommended(for: .linux, name: "Ubuntu", host: .fixture)
        #expect(config.cpuCount == 6)
        #expect(config.memorySize == .gibibytes(8))
        #expect(config.diskSize == .gibibytes(32))
        #expect(config.isRosettaEnabled)
    }

    @Test("macOS guests get at least 4 GB and 80 GB of disk")
    func macOSFloor() {
        var smallHost = HostCapabilities.fixture
        smallHost.physicalMemory = .gibibytes(8)
        smallHost.cpuCount = 8
        let config = VirtualMachineConfiguration.recommended(for: .macOS, name: "macOS", host: smallHost)
        #expect(config.memorySize == .gibibytes(4))
        #expect(config.diskSize == .gibibytes(80))
        #expect(!config.isRosettaEnabled)
    }

    @Test("recommended configurations are always valid", arguments: GuestOperatingSystem.allCases)
    func alwaysValid(guest: GuestOperatingSystem) {
        let config = VirtualMachineConfiguration.recommended(for: guest, name: "New", host: .fixture)
        #expect(ConfigurationValidator(host: .fixture).issues(in: config).isEmpty)
    }
}
