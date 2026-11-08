// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Testing
import Virtualization
@testable import NestVirtualization

/// Engine tests that run without the virtualization entitlement: they check what NestSuite asks the
/// framework for, not whether a guest boots (see Scripts/integration-boot-test.sh for that).
@MainActor
@Suite("Engine")
struct EngineTests {
    let directory: URL
    let library: VirtualMachineLibrary

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "EngineTests-\(UUID().uuidString)")
        library = VirtualMachineLibrary(rootURL: directory)
    }

    private func machine(
        _ mutate: (inout VirtualMachineConfiguration) -> Void = { _ in }
    ) throws -> (VirtualMachineBundle, VirtualMachineConfiguration) {
        var config = VirtualMachineConfiguration(
            name: "test", guest: .linux, cpuCount: 2, memorySize: .gibibytes(2), diskSize: .gibibytes(8),
            isRosettaEnabled: false
        )
        mutate(&config)
        return try (library.createBundle(for: config), config)
    }

    // MARK: Preparation

    @Test("the disk image is sparse and has the configured size")
    func sparseDisk() throws {
        let (bundle, _) = try machine()
        try MachinePreparation(bundle: bundle).ensureDiskImage(size: .gibibytes(8))
        let values = try bundle.diskImageURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        #expect(values.fileSize == 8 * 1024 * 1024 * 1024)
        #expect((values.totalFileAllocatedSize ?? .max) < 1024 * 1024, "a new disk must not occupy space")
    }

    @Test("an existing disk is never overwritten")
    func keepsDisk() throws {
        let (bundle, _) = try machine()
        try Data("guest data".utf8).write(to: bundle.diskImageURL)
        try MachinePreparation(bundle: bundle).ensureDiskImage(size: .gibibytes(8))
        #expect(try Data(contentsOf: bundle.diskImageURL) == Data("guest data".utf8))
    }

    @Test("identity files are created once and stay stable")
    func stableIdentity() throws {
        let (bundle, _) = try machine()
        let preparation = MachinePreparation(bundle: bundle)
        let identifier = try preparation.machineIdentifier().dataRepresentation
        let mac = try preparation.macAddress().string
        #expect(try preparation.machineIdentifier().dataRepresentation == identifier)
        #expect(try preparation.macAddress().string == mac)
        _ = try preparation.efiVariableStore()
        #expect(FileManager.default.fileExists(atPath: bundle.efiVariableStoreURL.path(percentEncoded: false)))
    }

    // MARK: Builder

    @Test("a Linux machine gets paravirtualized hardware")
    func hardware() throws {
        let (bundle, config) = try machine()
        let built = try ConfigurationBuilder(configuration: config, bundle: bundle).build()
        defer { built.release() }
        let machine = built.configuration
        #expect(machine.cpuCount == 2)
        #expect(machine.memorySize == 2 * 1024 * 1024 * 1024)
        #expect(machine.bootLoader is VZEFIBootLoader)
        #expect(machine.storageDevices.count == 1)
        #expect(machine.storageDevices.first is VZVirtioBlockDeviceConfiguration)
        #expect(machine.networkDevices.first?.attachment is VZNATNetworkDeviceAttachment)
        #expect(machine.graphicsDevices.first is VZVirtioGraphicsDeviceConfiguration)
        #expect(machine.audioDevices.first is VZVirtioSoundDeviceConfiguration)
        #expect(machine.memoryBalloonDevices.count == 1)
        #expect(machine.entropyDevices.count == 1)
        #expect(machine.directorySharingDevices.isEmpty)
    }

    @Test("an installer image is attached read-only as a USB drive")
    func installer() throws {
        let (bundle, config) = try machine()
        let iso = directory.appending(path: "installer.iso")
        try Data(repeating: 0, count: 4096).write(to: iso)
        var builder = ConfigurationBuilder(configuration: config, bundle: bundle)
        builder.bootMedia = .installer(iso)
        let built = try builder.build()
        defer { built.release() }
        let usb = try #require(built.configuration.storageDevices.last as? VZUSBMassStorageDeviceConfiguration)
        let image = try #require(usb.attachment as? VZDiskImageStorageDeviceAttachment)
        #expect(image.isReadOnly)
    }

    @Test("a missing installer image is reported, not ignored")
    func missingInstaller() throws {
        let (bundle, config) = try machine()
        var builder = ConfigurationBuilder(configuration: config, bundle: bundle)
        builder.bootMedia = .installer(URL(filePath: "/nonexistent.iso"))
        #expect(throws: EngineError.bootMediaMissing(path: "/nonexistent.iso")) { try builder.build() }
    }

    @Test("offline machines get no network device")
    func offline() throws {
        let (bundle, config) = try machine { $0.network = .disconnected }
        let built = try ConfigurationBuilder(configuration: config, bundle: bundle).build()
        defer { built.release() }
        #expect(built.configuration.networkDevices.isEmpty)
    }

    @Test("the clipboard setting reaches the SPICE agent")
    func clipboard() throws {
        let (bundle, config) = try machine { $0.isClipboardSharingEnabled = false }
        let built = try ConfigurationBuilder(configuration: config, bundle: bundle).build()
        defer { built.release() }
        let console = try #require(built.configuration.consoleDevices.first as? VZVirtioConsoleDeviceConfiguration)
        let agent = try #require(console.ports[0]?.attachment as? VZSpiceAgentPortAttachment)
        #expect(agent.sharesClipboard == false)
    }

    @Test("shared folders become virtiofs devices tagged with their name")
    func sharedFolders() throws {
        let folder = directory.appending(path: "project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try folder.bookmarkData()
        let (bundle, config) = try machine {
            $0.sharedFolders = [SharedFolder(name: "workspace", bookmark: bookmark, isReadOnly: true)]
        }
        let built = try ConfigurationBuilder(configuration: config, bundle: bundle).build()
        defer { built.release() }
        let device = try #require(built.configuration.directorySharingDevices
            .first as? VZVirtioFileSystemDeviceConfiguration)
        #expect(device.tag == "workspace")
    }

    @Test("a shared folder that no longer exists is reported")
    func vanishedFolder() throws {
        let folder = directory.appending(path: "gone")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try folder.bookmarkData()
        try FileManager.default.removeItem(at: folder)
        let (bundle, config) = try machine { $0.sharedFolders = [SharedFolder(name: "gone", bookmark: bookmark)] }
        #expect(throws: EngineError.sharedFolderUnavailable(name: "gone")) {
            try ConfigurationBuilder(configuration: config, bundle: bundle).build()
        }
    }

    @Test("macOS guests are rejected until they are supported")
    func macOSGuest() throws {
        let (bundle, _) = try machine()
        let mac = VirtualMachineConfiguration(
            name: "mac", guest: .macOS, cpuCount: 4, memorySize: .gibibytes(8), diskSize: .gibibytes(80)
        )
        #expect(throws: EngineError.guestNotYetSupported(.macOS)) {
            try ConfigurationBuilder(configuration: mac, bundle: bundle).build()
        }
    }

    // MARK: Session

    @Test("a machine locked by another process cannot start and stays stopped")
    func lockedSession() async throws {
        let (bundle, config) = try machine()
        let lock = try BundleLock(bundle: bundle)
        defer { lock.release() }
        let session = VirtualMachineSession(bundle: bundle, configuration: config)
        await #expect(throws: EngineError.inUseByAnotherProcess) { try await session.start() }
        #expect(session.state == .stopped)
        #expect(session.machine == nil)
    }

    @Test("stopping a machine that is not running is an error")
    func stopWhenStopped() async throws {
        let (bundle, config) = try machine()
        let session = VirtualMachineSession(bundle: bundle, configuration: config)
        #expect(throws: EngineError.notRunning) { try session.requestStop() }
        await #expect(throws: EngineError.notRunning) { try await session.forceStop() }
    }

    @Test("a bundle with a saved state starts out suspended")
    func suspendedOnLaunch() throws {
        let (bundle, config) = try machine()
        try Data("state".utf8).write(to: bundle.savedStateURL)
        #expect(VirtualMachineSession(bundle: bundle, configuration: config).state == .suspended)
    }
}
