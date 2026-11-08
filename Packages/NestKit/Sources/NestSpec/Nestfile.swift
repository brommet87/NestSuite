// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

/// A declarative description of one or more virtual machines, checked into a project repository.
///
/// The format is specified in `docs/nestfile.md`. Example:
///
/// ```yaml
/// version: 1
/// machines:
///   dev:
///     guest: linux
///     image: ubuntu-24.04
///     cpus: 4
///     memory: 8GiB
///     shares:
///       - host: .
///         tag: workspace
///     ports: [3000, "8080:80"]
/// ```
public struct Nestfile: Hashable, Sendable {
    public static let supportedVersion = 1
    public static let defaultFileNames = ["Nestfile.yml", "Nestfile.yaml", "Nestfile"]

    /// The file this was loaded from; relative paths in the file resolve against its directory.
    public let url: URL
    public let version: Int
    /// Machines in the order they appear in the file.
    public let machines: [MachineSpec]

    public init(url: URL, version: Int, machines: [MachineSpec]) {
        self.url = url
        self.version = version
        self.machines = machines
    }

    public var directoryURL: URL {
        url.deletingLastPathComponent()
    }
}

/// One machine in a Nestfile.
public struct MachineSpec: Hashable, Sendable {
    public var name: String
    public var guest: GuestOperatingSystem
    /// An image identifier from the NestSuite catalog (e.g. `ubuntu-24.04`) or a path/URL. Used from 0.2.
    public var image: String?
    public var cpus: Amount<Int>
    public var memory: Amount<ByteCount>
    public var disk: Amount<ByteCount>
    /// `nil` means "on when available" for Linux guests.
    public var rosetta: Bool?
    public var clipboard: Bool
    public var network: NetworkMode
    public var shares: [ShareSpec]
    public var ports: [PortForward]
    public var provision: ProvisionSpec?
    public var hooks: HooksSpec

    /// The YAML line where the machine is defined, for diagnostics.
    public var line: Int?

    public init(
        name: String,
        guest: GuestOperatingSystem,
        image: String? = nil,
        cpus: Amount<Int> = .auto,
        memory: Amount<ByteCount> = .auto,
        disk: Amount<ByteCount> = .auto,
        rosetta: Bool? = nil,
        clipboard: Bool = true,
        network: NetworkMode = .nat,
        shares: [ShareSpec] = [],
        ports: [PortForward] = [],
        provision: ProvisionSpec? = nil,
        hooks: HooksSpec = HooksSpec(),
        line: Int? = nil
    ) {
        self.name = name
        self.guest = guest
        self.image = image
        self.cpus = cpus
        self.memory = memory
        self.disk = disk
        self.rosetta = rosetta
        self.clipboard = clipboard
        self.network = network
        self.shares = shares
        self.ports = ports
        self.provision = provision
        self.hooks = hooks
        self.line = line
    }
}

/// A resource value that is either chosen automatically for the host or fixed.
public enum Amount<Value: Hashable & Sendable>: Hashable, Sendable {
    case auto
    case fixed(Value)

    public func resolved(default value: Value) -> Value {
        switch self {
        case .auto: value
        case let .fixed(fixed): fixed
        }
    }
}

/// A host folder shared into the guest via virtiofs.
public struct ShareSpec: Hashable, Sendable {
    /// Absolute host path (relative paths in the file are resolved against the Nestfile’s folder).
    public var hostURL: URL
    /// The virtiofs tag the guest mounts, e.g. `mount -t virtiofs workspace /workspace`.
    public var tag: String
    public var readOnly: Bool

    public init(hostURL: URL, tag: String, readOnly: Bool = false) {
        self.hostURL = hostURL
        self.tag = tag
        self.readOnly = readOnly
    }
}

/// Forward a host port to a guest port.
public struct PortForward: Hashable, Sendable {
    public enum TransportProtocol: String, Hashable, Sendable, CaseIterable {
        case tcp
        case udp
    }

    public var hostPort: Int
    public var guestPort: Int
    public var transport: TransportProtocol

    public init(hostPort: Int, guestPort: Int, transport: TransportProtocol = .tcp) {
        self.hostPort = hostPort
        self.guestPort = guestPort
        self.transport = transport
    }
}

/// First-boot provisioning.
public struct ProvisionSpec: Hashable, Sendable {
    /// A cloud-init user-data file, resolved against the Nestfile’s folder.
    public var cloudInit: URL?

    public init(cloudInit: URL? = nil) {
        self.cloudInit = cloudInit
    }
}

/// Scripts run on the host around lifecycle events.
public struct HooksSpec: Hashable, Sendable {
    public var preStart: URL?
    public var postStart: URL?
    public var postProvision: URL?
    public var preStop: URL?

    public init(preStart: URL? = nil, postStart: URL? = nil, postProvision: URL? = nil, preStop: URL? = nil) {
        self.preStart = preStart
        self.postStart = postStart
        self.postProvision = postProvision
        self.preStop = preStop
    }

    public var all: [(event: String, url: URL)] {
        [("preStart", preStart), ("postStart", postStart), ("postProvision", postProvision), ("preStop", preStop)]
            .compactMap { event, url in url.map { (event, $0) } }
    }
}
