// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Virtualization

/// Optional media attached for one start, e.g. an installer image. Not part of the saved configuration.
public enum BootMedia: Equatable, Sendable {
    case none
    /// A bootable ISO, attached read-only as a USB drive. EFI boots from it when the disk is empty.
    case installer(URL)
}

/// Where the guest’s serial console goes.
public enum ConsoleOutput {
    /// Appended to `Console.log` in the bundle (the default; `nestctl logs` reads it).
    case logFile
    /// Connected to the given handles, e.g. the terminal for `nestctl run --console`.
    case handles(read: FileHandle?, write: FileHandle)
    case none
}

/// The result of building: the framework configuration plus resources that must be released when
/// the machine stops (security-scoped folder access, open file handles).
@MainActor
public final class BuiltConfiguration {
    public let configuration: VZVirtualMachineConfiguration
    private var accessedURLs: [URL]
    private var openHandles: [FileHandle]

    init(configuration: VZVirtualMachineConfiguration, accessedURLs: [URL], openHandles: [FileHandle]) {
        self.configuration = configuration
        self.accessedURLs = accessedURLs
        self.openHandles = openHandles
    }

    /// Ends security-scoped access and closes log files. Safe to call more than once.
    public func release() {
        accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        accessedURLs = []
        openHandles.forEach { try? $0.close() }
        openHandles = []
    }
}

/// Translates a ``VirtualMachineConfiguration`` into a `VZVirtualMachineConfiguration`.
///
/// This is the only place that decides which virtual hardware a guest gets. Everything is
/// paravirtualized (virtio) for speed; nothing is emulated.
@MainActor
public struct ConfigurationBuilder {
    public static let rosettaTag = "rosetta"

    public let configuration: VirtualMachineConfiguration
    public let bundle: VirtualMachineBundle
    public var bootMedia: BootMedia = .none
    public var console: ConsoleOutput = .logFile

    public init(configuration: VirtualMachineConfiguration, bundle: VirtualMachineBundle) {
        self.configuration = configuration
        self.bundle = bundle
    }

    public var consoleLogURL: URL {
        bundle.url.appending(path: "Console.log")
    }

    /// Prepares the bundle files and builds the configuration. Call `validate()` on the result before
    /// creating a machine; ``VirtualMachineSession`` does this for you.
    public func build() throws -> BuiltConfiguration {
        guard configuration.guest == .linux else { throw EngineError.guestNotYetSupported(configuration.guest) }

        let preparation = MachinePreparation(bundle: bundle)
        try preparation.ensureDiskImage(size: configuration.diskSize)

        let vzConfiguration = VZVirtualMachineConfiguration()
        vzConfiguration.cpuCount = configuration.cpuCount
        vzConfiguration.memorySize = configuration.memorySize.bytes

        let platform = VZGenericPlatformConfiguration()
        platform.machineIdentifier = try preparation.machineIdentifier()
        vzConfiguration.platform = platform

        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = try preparation.efiVariableStore()
        vzConfiguration.bootLoader = bootLoader

        vzConfiguration.storageDevices = try storageDevices()
        vzConfiguration.networkDevices = try networkDevices(preparation: preparation)
        vzConfiguration.graphicsDevices = [graphicsDevice()]
        vzConfiguration.keyboards = [VZUSBKeyboardConfiguration()]
        vzConfiguration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        vzConfiguration.audioDevices = [soundDevice()]
        vzConfiguration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        vzConfiguration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        vzConfiguration.consoleDevices = [clipboardDevice()]

        var openHandles: [FileHandle] = []
        if let serial = try serialPort(openHandles: &openHandles) {
            vzConfiguration.serialPorts = [serial]
        }

        var accessedURLs: [URL] = []
        do {
            vzConfiguration.directorySharingDevices = try directorySharingDevices(accessedURLs: &accessedURLs)
        } catch {
            accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            openHandles.forEach { try? $0.close() }
            throw error
        }
        return BuiltConfiguration(configuration: vzConfiguration, accessedURLs: accessedURLs, openHandles: openHandles)
    }

    // MARK: - Devices

    func storageDevices() throws -> [VZStorageDeviceConfiguration] {
        let disk = try VZDiskImageStorageDeviceAttachment(
            url: bundle.diskImageURL, readOnly: false, cachingMode: .automatic, synchronizationMode: .fsync
        )
        var devices: [VZStorageDeviceConfiguration] = [VZVirtioBlockDeviceConfiguration(attachment: disk)]
        // cloud-init seed (label CIDATA), read-only. Kept attached: cloud-init only acts on a new instance id.
        if FileManager.default.fileExists(atPath: bundle.cloudInitSeedURL.path(percentEncoded: false)) {
            let seed = try VZDiskImageStorageDeviceAttachment(url: bundle.cloudInitSeedURL, readOnly: true)
            devices.append(VZVirtioBlockDeviceConfiguration(attachment: seed))
        }
        if case let .installer(url) = bootMedia {
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                throw EngineError.bootMediaMissing(path: url.path(percentEncoded: false))
            }
            let image = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: true)
            devices.append(VZUSBMassStorageDeviceConfiguration(attachment: image))
        }
        return devices
    }

    func networkDevices(preparation: MachinePreparation) throws -> [VZNetworkDeviceConfiguration] {
        switch configuration.network {
        case .disconnected:
            return []
        case .nat:
            let device = VZVirtioNetworkDeviceConfiguration()
            device.attachment = VZNATNetworkDeviceAttachment()
            device.macAddress = try preparation.macAddress()
            return [device]
        }
    }

    func graphicsDevice() -> VZGraphicsDeviceConfiguration {
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(
            widthInPixels: configuration.display.widthInPixels,
            heightInPixels: configuration.display.heightInPixels
        )]
        return graphics
    }

    /// Sound output to the Mac’s speakers. Microphone input is deliberately not attached: it needs
    /// explicit consent and will be an opt-in setting.
    func soundDevice() -> VZAudioDeviceConfiguration {
        let sound = VZVirtioSoundDeviceConfiguration()
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        sound.streams = [output]
        return sound
    }

    /// The SPICE agent port carries the shared clipboard (guest needs `spice-vdagent`).
    func clipboardDevice() -> VZConsoleDeviceConfiguration {
        let console = VZVirtioConsoleDeviceConfiguration()
        let port = VZVirtioConsolePortConfiguration()
        port.name = VZSpiceAgentPortAttachment.spiceAgentPortName
        let agent = VZSpiceAgentPortAttachment()
        agent.sharesClipboard = configuration.isClipboardSharingEnabled
        port.attachment = agent
        console.ports[0] = port
        return console
    }

    func serialPort(openHandles: inout [FileHandle]) throws -> VZSerialPortConfiguration? {
        let attachment: VZSerialPortAttachment
        switch console {
        case .none:
            return nil
        case let .handles(read, write):
            attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: read, fileHandleForWriting: write)
        case .logFile:
            let path = consoleLogURL.path(percentEncoded: false)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: consoleLogURL)
            try handle.truncate(atOffset: 0) // one log per run keeps it readable
            openHandles.append(handle)
            attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: nil, fileHandleForWriting: handle)
        }
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = attachment
        return serial
    }

    /// One virtiofs device per shared folder (tag = folder name), plus Rosetta when enabled.
    func directorySharingDevices(accessedURLs: inout [URL]) throws -> [VZDirectorySharingDeviceConfiguration] {
        var devices: [VZDirectorySharingDeviceConfiguration] = []
        for folder in configuration.sharedFolders {
            do {
                try VZVirtioFileSystemDeviceConfiguration.validateTag(folder.name)
            } catch {
                throw EngineError.invalidSharedFolderTag(folder.name)
            }
            let url = try resolve(folder, accessedURLs: &accessedURLs)
            let device = VZVirtioFileSystemDeviceConfiguration(tag: folder.name)
            device.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: url, readOnly: folder.isReadOnly))
            devices.append(device)
        }
        if configuration.isRosettaEnabled {
            try devices.append(rosettaDevice())
        }
        return devices
    }

    private func rosettaDevice() throws -> VZDirectorySharingDeviceConfiguration {
        #if arch(arm64)
            do {
                let device = VZVirtioFileSystemDeviceConfiguration(tag: Self.rosettaTag)
                device.share = try VZLinuxRosettaDirectoryShare()
                return device
            } catch {
                throw EngineError.rosettaNotInstalled
            }
        #else
            throw EngineError.rosettaNotInstalled
        #endif
    }

    /// Resolves a bookmark: security-scoped first (sandboxed app), plain second (`nestctl`).
    private func resolve(_ folder: SharedFolder, accessedURLs: inout [URL]) throws -> URL {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: folder.bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale
        ) {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
            return url
        }
        if let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        {
            return url
        }
        throw EngineError.sharedFolderUnavailable(name: folder.name)
    }
}
