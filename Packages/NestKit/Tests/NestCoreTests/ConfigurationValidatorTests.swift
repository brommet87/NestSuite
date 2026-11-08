// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import Testing
@testable import NestCore

@Suite("ConfigurationValidator")
struct ConfigurationValidatorTests {
    let validator = ConfigurationValidator(host: .fixture)

    @Test("a reasonable Linux configuration has no issues")
    func validConfiguration() {
        #expect(validator.issues(in: .fixture()).isEmpty)
        #expect(validator.canStart(.fixture()))
    }

    @Test("names must not be empty or whitespace", arguments: ["", "   ", "\n\t"])
    func emptyName(name: String) {
        #expect(validator.issues(in: .fixture(name: name)) == [.emptyName])
    }

    @Test("names longer than the limit are rejected")
    func longName() {
        let name = String(repeating: "a", count: ConfigurationValidator.maximumNameLength + 1)
        #expect(validator.issues(in: .fixture(name: name)) == [.nameTooLong(maximum: 64)])
    }

    @Test("CPU count outside the host range is an error", arguments: [0, 13, 64])
    func cpuOutOfRange(cpus: Int) {
        #expect(validator.issues(in: .fixture(cpuCount: cpus)) == [.cpuCountOutOfRange(allowed: 1 ... 12)])
    }

    @Test("memory above the framework maximum is an error")
    func memoryTooLarge() {
        let issues = validator.issues(in: .fixture(memorySize: .gibibytes(64)))
        #expect(issues == [.memoryOutOfRange(minimum: .mebibytes(128), maximum: .gibibytes(32))])
    }

    @Test("memory that starves the host is a warning, not an error")
    func memoryStarvesHost() {
        let config = VirtualMachineConfiguration.fixture(memorySize: .gibibytes(30))
        #expect(validator.issues(in: config) == [.memoryLeavesTooLittleForHost(recommendedMaximum: .gibibytes(28))])
        #expect(validator.canStart(config))
    }

    @Test("disk minimum depends on the guest")
    func diskTooSmall() {
        #expect(validator.issues(in: .fixture(diskSize: .gibibytes(4))) == [.diskTooSmall(minimum: .gibibytes(8))])
        let mac = VirtualMachineConfiguration.fixture(guest: .macOS, diskSize: .gibibytes(32))
        #expect(validator.issues(in: mac) == [.diskTooSmall(minimum: .gibibytes(40))])
    }

    @Test("Rosetta is only valid for Linux guests on hosts that have it")
    func rosetta() {
        var linux = VirtualMachineConfiguration.fixture()
        linux.isRosettaEnabled = true
        #expect(validator.issues(in: linux).isEmpty)

        var hostWithoutRosetta = HostCapabilities.fixture
        hostWithoutRosetta.isRosettaAvailable = false
        #expect(ConfigurationValidator(host: hostWithoutRosetta).issues(in: linux) == [.rosettaUnavailableOnHost])

        var mac = VirtualMachineConfiguration.fixture(guest: .macOS, diskSize: .gibibytes(80))
        mac.isRosettaEnabled = true
        #expect(validator.issues(in: mac) == [.rosettaUnsupportedForGuest])
    }

    @Test("the initializer never enables Rosetta for macOS guests")
    func initializerNormalizesRosetta() {
        let mac = VirtualMachineConfiguration(
            name: "Mac", guest: .macOS, cpuCount: 4, memorySize: .gibibytes(8), diskSize: .gibibytes(80),
            isRosettaEnabled: true
        )
        #expect(mac.isRosettaEnabled == false)
    }

    @Test("macOS guests require host support")
    func macOSUnsupported() {
        var host = HostCapabilities.fixture
        host.supportsMacOSGuests = false
        let mac = VirtualMachineConfiguration.fixture(guest: .macOS, diskSize: .gibibytes(80))
        #expect(ConfigurationValidator(host: host).issues(in: mac) == [.macOSGuestsUnsupportedOnHost])
    }

    @Test("shared folder names must be unique, ignoring case")
    func duplicateSharedFolders() {
        var config = VirtualMachineConfiguration.fixture()
        config.sharedFolders = [
            SharedFolder(name: "Home", bookmark: Data()),
            SharedFolder(name: "home", bookmark: Data()),
        ]
        #expect(validator.issues(in: config) == [.duplicateSharedFolderName("home")])
    }

    @Test("errors are listed before warnings")
    func errorsFirst() {
        let config = VirtualMachineConfiguration.fixture(name: "", memorySize: .gibibytes(30))
        let issues = validator.issues(in: config)
        #expect(issues.first == .emptyName)
        #expect(issues.last?.severity == .warning)
    }
}
