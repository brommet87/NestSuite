// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore
import NestSpec

// JSON shapes of `nestctl --json`. They are a public interface: fields may be added, but never
// renamed or removed without a major version bump. Sizes are always bytes.

struct MachineDTO: Encodable, Equatable {
    let name: String
    let id: UUID?
    let guest: String?
    let cpus: Int?
    let memoryBytes: UInt64?
    let diskBytes: UInt64?
    let network: String?
    let rosetta: Bool?
    let clipboard: Bool?
    let sharedFolders: Int?
    let status: String
    let problem: String?
    let path: String

    init(entry: LibraryEntry) {
        path = entry.id.path(percentEncoded: false)
        switch entry {
        case let .machine(_, config):
            name = config.name
            id = config.id
            guest = config.guest.rawValue
            cpus = config.cpuCount
            memoryBytes = config.memorySize.bytes
            diskBytes = config.diskSize.bytes
            network = config.network.rawValue
            rosetta = config.guest.supportsRosetta ? config.isRosettaEnabled : nil
            clipboard = config.isClipboardSharingEnabled
            sharedFolders = config.sharedFolders.count
            status = "stopped"
            problem = nil
        case let .damaged(bundle, error):
            name = bundle.url.deletingPathExtension().lastPathComponent
            id = nil
            guest = nil
            cpus = nil
            memoryBytes = nil
            diskBytes = nil
            network = nil
            rosetta = nil
            clipboard = nil
            sharedFolders = nil
            status = "damaged"
            problem = error.cliDescription
        }
    }
}

struct HostDTO: Encodable, Equatable {
    let cpus: Int
    let memoryBytes: UInt64
    let cpuRange: [Int]
    let memoryRangeBytes: [UInt64]
    let recommendedMaximumMemoryBytes: UInt64
    let rosettaAvailable: Bool
    let macOSGuestsSupported: Bool

    init(_ host: HostCapabilities) {
        cpus = host.cpuCount
        memoryBytes = host.physicalMemory.bytes
        cpuRange = [host.minimumCPUCount, host.maximumCPUCount]
        memoryRangeBytes = [host.minimumMemorySize.bytes, host.maximumMemorySize.bytes]
        recommendedMaximumMemoryBytes = host.recommendedMaximumMemory.bytes
        rosettaAvailable = host.isRosettaAvailable
        macOSGuestsSupported = host.supportsMacOSGuests
    }
}

struct ValidationDTO: Encodable, Equatable {
    struct Diagnostic: Encodable, Equatable {
        let severity: String
        let path: String
        let line: Int?
        let message: String
    }

    struct Machine: Encodable, Equatable {
        let name: String
        let guest: String
        let cpus: Int
        let memoryBytes: UInt64
        let diskBytes: UInt64
        let ports: [String]
        let shares: [String]
    }

    let file: String
    let valid: Bool
    let machines: [Machine]
    let diagnostics: [Diagnostic]
}

extension VirtualMachineLibraryError {
    var cliDescription: String {
        switch self {
        case .configurationMissing: "config.json is missing"
        case let .configurationUnreadable(_, reason): "config.json is unreadable: \(reason)"
        case let .unsupportedSchemaVersion(found, supported): "format \(found) is newer than supported \(supported)"
        case let .bundleAlreadyExists(url): "\(url.lastPathComponent) already exists"
        case let .nameInUse(name): "a machine named “\(name)” already exists"
        }
    }
}

extension PortForward {
    var shortDescription: String {
        let base = hostPort == guestPort ? "\(hostPort)" : "\(hostPort):\(guestPort)"
        return transport == .tcp ? base : "\(base)/\(transport.rawValue)"
    }
}
