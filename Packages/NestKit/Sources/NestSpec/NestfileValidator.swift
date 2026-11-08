// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

/// A finding about a syntactically valid Nestfile, checked against the host and the file system.
public struct NestfileDiagnostic: Hashable, Sendable {
    public enum Severity: String, Hashable, Sendable {
        case error
        case warning
    }

    public let severity: Severity
    public let machine: String?
    public let path: String
    public let line: Int?
    public let message: String

    public init(severity: Severity, machine: String?, path: String, line: Int?, message: String) {
        self.severity = severity
        self.machine = machine
        self.path = path
        self.line = line
        self.message = message
    }
}

/// Semantic checks that need the host or the file system: resource limits, missing share folders,
/// port collisions between machines, missing hook scripts.
public struct NestfileValidator: Sendable {
    public let host: HostCapabilities

    public init(host: HostCapabilities) {
        self.host = host
    }

    public func diagnostics(for nestfile: Nestfile, fileManager: FileManager = .default) -> [NestfileDiagnostic] {
        var usedHostPorts: [String: String] = [:] // "tcp/8080" → machine name
        var diagnostics: [NestfileDiagnostic] = []
        for machine in nestfile.machines {
            var checker = MachineChecker(machine: machine, fileManager: fileManager)
            checker.checkHardware(host: host)
            checker.checkShares()
            checker.checkPorts(usedHostPorts: &usedHostPorts)
            checker.checkFiles()
            diagnostics += checker.findings
        }
        // Errors first, file order preserved within each group.
        return diagnostics.filter { $0.severity == .error } + diagnostics.filter { $0.severity == .warning }
    }
}

/// Collects the findings for one machine. Each check covers one section of the machine definition.
private struct MachineChecker {
    let machine: MachineSpec
    let fileManager: FileManager
    private(set) var findings: [NestfileDiagnostic] = []

    private mutating func add(_ severity: NestfileDiagnostic.Severity, _ key: String, _ message: String) {
        let base = "machines.\(machine.name)"
        findings.append(NestfileDiagnostic(
            severity: severity, machine: machine.name,
            path: key.isEmpty ? base : "\(base).\(key)", line: machine.line, message: message
        ))
    }

    /// Hardware and guest rules, using the same validator as the app.
    mutating func checkHardware(host: HostCapabilities) {
        for issue in ConfigurationValidator(host: host).issues(in: machine.configuration(host: host)) {
            add(issue.severity == .error ? .error : .warning, issue.specKey, issue.englishDescription)
        }
        if machine.rosetta == true, machine.guest != .linux {
            add(.error, "rosetta", "Rosetta is only available for Linux guests")
        }
        if machine.guest == .linux, machine.image == nil {
            add(.warning, "image", "no image set; `nestctl up` will ask which distribution to install")
        }
    }

    mutating func checkShares() {
        var tags = Set<String>()
        for (index, share) in machine.shares.enumerated() {
            let path = share.hostURL.path(percentEncoded: false)
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
                add(.error, "shares[\(index)].host", "folder “\(path)” does not exist")
            } else if !isDirectory.boolValue {
                add(.error, "shares[\(index)].host", "“\(path)” is a file; shares must be folders")
            }
            if !tags.insert(share.tag.lowercased()).inserted {
                add(.error, "shares[\(index)].tag", "tag “\(share.tag)” is used twice; give each share a unique tag")
            }
        }
    }

    /// A host port can be forwarded only once across all machines.
    mutating func checkPorts(usedHostPorts: inout [String: String]) {
        for (index, forward) in machine.ports.enumerated() {
            let port = "\(forward.hostPort)/\(forward.transport.rawValue)"
            if let owner = usedHostPorts[port] {
                let target = owner == machine.name ? "this machine" : "machine “\(owner)”"
                add(.error, "ports[\(index)]", "host port \(port) is already forwarded by \(target)")
            } else {
                usedHostPorts[port] = machine.name
            }
            if forward.hostPort < 1024 {
                let message = "host port \(forward.hostPort) is privileged; macOS may refuse to bind it"
                add(.warning, "ports[\(index)]", message)
            }
        }
    }

    /// Provisioning files and hook scripts must exist; hooks must be executable.
    mutating func checkFiles() {
        if let cloudInit = machine.provision?.cloudInit?.path(percentEncoded: false),
           !fileManager.fileExists(atPath: cloudInit)
        {
            add(.error, "provision.cloudInit", "file “\(cloudInit)” does not exist")
        }
        for (event, url) in machine.hooks.all {
            let path = url.path(percentEncoded: false)
            if !fileManager.fileExists(atPath: path) {
                add(.error, "hooks.\(event)", "script “\(path)” does not exist")
            } else if !fileManager.isExecutableFile(atPath: path) {
                add(.error, "hooks.\(event)", "script “\(path)” is not executable (chmod +x)")
            }
        }
    }
}

public extension MachineSpec {
    /// The concrete configuration for this host: `auto` values use NestSuite’s recommendations.
    func configuration(
        host: HostCapabilities,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) -> VirtualMachineConfiguration {
        let recommended = VirtualMachineConfiguration.recommended(for: guest, name: name, host: host)
        return VirtualMachineConfiguration(
            id: id,
            name: name,
            guest: guest,
            cpuCount: cpus.resolved(default: recommended.cpuCount),
            memorySize: memory.resolved(default: recommended.memorySize),
            diskSize: disk.resolved(default: recommended.diskSize),
            network: network,
            isClipboardSharingEnabled: clipboard,
            isRosettaEnabled: rosetta ?? recommended.isRosettaEnabled,
            createdAt: createdAt
        )
    }
}

extension ConfigurationIssue {
    /// The Nestfile key an issue refers to.
    var specKey: String {
        switch self {
        case .emptyName, .nameTooLong: ""
        case .cpuCountOutOfRange: "cpus"
        case .memoryOutOfRange, .memoryLeavesTooLittleForHost: "memory"
        case .diskTooSmall: "disk"
        case .rosettaUnsupportedForGuest, .rosettaUnavailableOnHost: "rosetta"
        case .macOSGuestsUnsupportedOnHost: "guest"
        case .duplicateSharedFolderName: "shares"
        case .unsupportedSchemaVersion: ""
        }
    }

    /// English text for developer tooling (the app shows localized text instead).
    public var englishDescription: String {
        switch self {
        case .emptyName: "the name is empty"
        case let .nameTooLong(maximum): "the name is longer than \(maximum) characters"
        case let .cpuCountOutOfRange(allowed):
            "cpus must be between \(allowed.lowerBound) and \(allowed.upperBound) on this Mac"
        case let .memoryOutOfRange(minimum, maximum):
            "memory must be between \(minimum) and \(maximum) on this Mac"
        case let .memoryLeavesTooLittleForHost(recommended):
            "memory leaves little for macOS; consider at most \(recommended)"
        case let .diskTooSmall(minimum): "disk must be at least \(minimum)"
        case .rosettaUnsupportedForGuest: "Rosetta is only available for Linux guests"
        case .rosettaUnavailableOnHost:
            "Rosetta is not installed on this Mac (softwareupdate --install-rosetta)"
        case .macOSGuestsUnsupportedOnHost: "macOS guests require a Mac with Apple silicon"
        case let .duplicateSharedFolderName(name): "shared folder name “\(name)” is used twice"
        case let .unsupportedSchemaVersion(found, supported):
            "format \(found) is newer than supported \(supported)"
        }
    }
}
