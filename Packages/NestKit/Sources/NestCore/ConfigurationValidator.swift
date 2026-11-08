// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation

/// A problem found in a ``VirtualMachineConfiguration``.
///
/// Issues carry structured data, not text. The UI turns them into localized, actionable messages,
/// so the same issue can be shown inline next to the offending field.
public enum ConfigurationIssue: Hashable, Sendable {
    public enum Severity: Sendable {
        /// The machine cannot start with this configuration.
        case error
        /// The machine starts, but the choice is likely a mistake (e.g. starving the host).
        case warning
    }

    case emptyName
    case nameTooLong(maximum: Int)
    case cpuCountOutOfRange(allowed: ClosedRange<Int>)
    case memoryOutOfRange(minimum: ByteCount, maximum: ByteCount)
    case memoryLeavesTooLittleForHost(recommendedMaximum: ByteCount)
    case diskTooSmall(minimum: ByteCount)
    case rosettaUnsupportedForGuest
    case rosettaUnavailableOnHost
    case macOSGuestsUnsupportedOnHost
    case duplicateSharedFolderName(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)

    public var severity: Severity {
        switch self {
        case .memoryLeavesTooLittleForHost: .warning
        default: .error
        }
    }
}

/// Checks a configuration against the host's capabilities before it is saved or started.
public struct ConfigurationValidator: Sendable {
    public static let maximumNameLength = 64
    public static let minimumDiskSize: [GuestOperatingSystem: ByteCount] = [
        .linux: .gibibytes(8),
        .macOS: .gibibytes(40),
    ]

    public let host: HostCapabilities

    public init(host: HostCapabilities) {
        self.host = host
    }

    /// All issues, errors first. An empty result means the configuration is valid.
    public func issues(in config: VirtualMachineConfiguration) -> [ConfigurationIssue] {
        let issues = formatIssues(config) + nameIssues(config) + resourceIssues(config) + integrationIssues(config)
        // Stable partition: errors first, original order preserved within each group.
        return issues.filter { $0.severity == .error } + issues.filter { $0.severity == .warning }
    }

    private func formatIssues(_ config: VirtualMachineConfiguration) -> [ConfigurationIssue] {
        guard config.schemaVersion > VirtualMachineConfiguration.currentSchemaVersion else { return [] }
        return [.unsupportedSchemaVersion(
            found: config.schemaVersion,
            supported: VirtualMachineConfiguration.currentSchemaVersion
        )]
    }

    private func nameIssues(_ config: VirtualMachineConfiguration) -> [ConfigurationIssue] {
        let trimmedName = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return [.emptyName]
        }
        if trimmedName.count > Self.maximumNameLength {
            return [.nameTooLong(maximum: Self.maximumNameLength)]
        }
        return []
    }

    private func resourceIssues(_ config: VirtualMachineConfiguration) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        let cpuRange = host.minimumCPUCount ... host.maximumCPUCount
        if !cpuRange.contains(config.cpuCount) {
            issues.append(.cpuCountOutOfRange(allowed: cpuRange))
        }
        if config.memorySize < host.minimumMemorySize || config.memorySize > host.maximumMemorySize {
            issues.append(.memoryOutOfRange(minimum: host.minimumMemorySize, maximum: host.maximumMemorySize))
        } else if config.memorySize > host.recommendedMaximumMemory {
            issues.append(.memoryLeavesTooLittleForHost(recommendedMaximum: host.recommendedMaximumMemory))
        }
        if let minimumDisk = Self.minimumDiskSize[config.guest], config.diskSize < minimumDisk {
            issues.append(.diskTooSmall(minimum: minimumDisk))
        }
        return issues
    }

    private func integrationIssues(_ config: VirtualMachineConfiguration) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        if config.isRosettaEnabled {
            if !config.guest.supportsRosetta {
                issues.append(.rosettaUnsupportedForGuest)
            } else if !host.isRosettaAvailable {
                issues.append(.rosettaUnavailableOnHost)
            }
        }
        if config.guest == .macOS, !host.supportsMacOSGuests {
            issues.append(.macOSGuestsUnsupportedOnHost)
        }
        var seenNames = Set<String>()
        for folder in config.sharedFolders where !seenNames.insert(folder.name.lowercased()).inserted {
            issues.append(.duplicateSharedFolderName(folder.name))
        }
        return issues
    }

    /// `true` when the configuration has no errors (warnings are allowed).
    public func canStart(_ config: VirtualMachineConfiguration) -> Bool {
        !issues(in: config).contains { $0.severity == .error }
    }
}
