// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import Virtualization

/// Errors while preparing or configuring a machine. Structured, so the app and `nestctl` can explain
/// each case and offer a fix.
public enum EngineError: Error, Equatable, Sendable {
    case guestNotYetSupported(GuestOperatingSystem)
    case diskCreationFailed(path: String, reason: String)
    case bootMediaMissing(path: String)
    case sharedFolderUnavailable(name: String)
    case invalidSharedFolderTag(String)
    case rosettaNotInstalled
    case invalidConfiguration(reason: String)
    case alreadyRunning
    case inUseByAnotherProcess
    case notRunning
    case startFailed(reason: String)
}

extension EngineError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .guestNotYetSupported(guest): "\(guest.rawValue) guests are not supported by this version yet"
        case let .diskCreationFailed(path, reason): "could not create the disk image at \(path): \(reason)"
        case let .bootMediaMissing(path): "the boot image \(path) does not exist"
        case let .sharedFolderUnavailable(name): "the shared folder “\(name)” is no longer available"
        case let .invalidSharedFolderTag(tag): "“\(tag)” is not a valid shared folder name for the guest"
        case .rosettaNotInstalled: "Rosetta is not installed (softwareupdate --install-rosetta)"
        case let .invalidConfiguration(reason): "the machine configuration is invalid: \(reason)"
        case .alreadyRunning: "the machine is already running"
        case .inUseByAnotherProcess: "the machine is running in another process (NestSuite app or another nestctl)"
        case .notRunning: "the machine is not running"
        case let .startFailed(reason): "the machine could not start: \(reason)"
        }
    }
}

/// Creates the per-machine files the engine needs on first start: disk image, EFI variable store,
/// machine identifier and MAC address. Idempotent: existing files are kept, so a machine keeps its
/// identity, network address and disk contents across starts.
public struct MachinePreparation: Sendable {
    public let bundle: VirtualMachineBundle

    public init(bundle: VirtualMachineBundle) {
        self.bundle = bundle
    }

    var macAddressURL: URL {
        bundle.url.appending(path: "MACAddress")
    }

    /// Creates a sparse raw disk image. On APFS it occupies no space until the guest writes.
    public func ensureDiskImage(size: ByteCount, fileManager: FileManager = .default) throws {
        let path = bundle.diskImageURL.path(percentEncoded: false)
        guard !fileManager.fileExists(atPath: path) else { return }
        guard fileManager.createFile(atPath: path, contents: nil) else {
            throw EngineError.diskCreationFailed(path: path, reason: "the file could not be created")
        }
        do {
            let handle = try FileHandle(forWritingTo: bundle.diskImageURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: size.bytes)
        } catch {
            try? fileManager.removeItem(atPath: path)
            throw EngineError.diskCreationFailed(path: path, reason: error.localizedDescription)
        }
    }

    /// The machine identifier, created once and then reused.
    public func machineIdentifier() throws -> VZGenericMachineIdentifier {
        if let data = try? Data(contentsOf: bundle.machineIdentifierURL),
           let identifier = VZGenericMachineIdentifier(dataRepresentation: data)
        {
            return identifier
        }
        let identifier = VZGenericMachineIdentifier()
        try identifier.dataRepresentation.write(to: bundle.machineIdentifierURL, options: .atomic)
        return identifier
    }

    /// The EFI variable store (boot entries), created once.
    public func efiVariableStore(fileManager: FileManager = .default) throws -> VZEFIVariableStore {
        if fileManager.fileExists(atPath: bundle.efiVariableStoreURL.path(percentEncoded: false)) {
            return VZEFIVariableStore(url: bundle.efiVariableStoreURL)
        }
        return try VZEFIVariableStore(creatingVariableStoreAt: bundle.efiVariableStoreURL)
    }

    /// A stable, locally administered MAC address, so the guest keeps its DHCP lease and hostname.
    public func macAddress() throws -> VZMACAddress {
        if let text = try? String(contentsOf: macAddressURL, encoding: .utf8),
           let address = VZMACAddress(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return address
        }
        let address = VZMACAddress.randomLocallyAdministered()
        try Data(address.string.utf8).write(to: macAddressURL, options: .atomic)
        return address
    }
}
