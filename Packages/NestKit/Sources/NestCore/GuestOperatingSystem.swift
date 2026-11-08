// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

/// The guest operating systems NestSuite can run.
///
/// Phase 1 supports Linux and macOS guests on Apple silicon through `Virtualization.framework`.
/// Windows is planned for a later phase (see `ROADMAP.md`); it is deliberately absent here so no
/// code path can pretend to support it.
public enum GuestOperatingSystem: String, Codable, CaseIterable, Sendable {
    case linux
    case macOS

    /// Whether the guest can use Rosetta to run x86-64 Linux binaries.
    public var supportsRosetta: Bool {
        self == .linux
    }

    /// Apple's macOS license allows at most two macOS virtual machines running at once per Mac.
    /// `Virtualization.framework` enforces the same limit.
    public var maximumConcurrentInstances: Int? {
        switch self {
        case .linux: nil
        case .macOS: 2
        }
    }
}
