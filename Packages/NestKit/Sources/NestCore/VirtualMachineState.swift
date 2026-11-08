// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

/// The lifecycle state of a virtual machine as shown to the user.
///
/// All transitions go through ``applying(_:)``, so the UI can never reach an impossible state
/// (for example "paused" without having been "running"). Invalid events return `nil` and are
/// rejected by the caller instead of being silently ignored.
public enum VirtualMachineState: Hashable, Sendable {
    case stopped
    case starting
    case running
    case pausing
    case paused
    case resuming
    case saving
    /// A saved state exists on disk; starting restores it instead of booting.
    case suspended
    case restoring
    case stopping
    case failed(VirtualMachineFailure)

    /// Whether a guest is currently using host resources.
    public var isActive: Bool {
        switch self {
        case .starting, .running, .pausing, .paused, .resuming, .saving, .restoring, .stopping: true
        case .stopped, .suspended, .failed: false
        }
    }

    /// Whether the state is a short-lived transition the user should see progress for.
    public var isTransitioning: Bool {
        switch self {
        case .starting, .pausing, .resuming, .saving, .restoring, .stopping: true
        default: false
        }
    }

    /// Whether the configuration may be edited. Only a fully stopped machine can be changed;
    /// a suspended machine's saved state depends on its current hardware.
    public var allowsConfigurationChanges: Bool {
        switch self {
        case .stopped, .failed: true
        default: false
        }
    }

    /// The state after `event`, or `nil` if the event is not allowed in this state.
    public func applying(_ event: VirtualMachineEvent) -> VirtualMachineState? {
        switch (self, event) {
        case (.stopped, .start), (.failed, .start): .starting
        case (.suspended, .start): .restoring
        case (.starting, .didStart), (.restoring, .didStart), (.resuming, .didResume): .running
        case (.running, .pause): .pausing
        case (.pausing, .didPause): .paused
        case (.paused, .resume): .resuming
        case (.running, .save), (.paused, .save): .saving
        case (.saving, .didSave): .suspended
        case (.suspended, .discardSavedState): .stopped
        case (.running, .stop), (.paused, .stop), (.starting, .stop): .stopping
        case (.stopping, .didStop), (.running, .didStop), (.paused, .didStop): .stopped
        case let (current, .didFail(failure)) where current.isActive: .failed(failure)
        default: nil
        }
    }
}

/// Things that happen to a virtual machine: user intents and engine callbacks.
public enum VirtualMachineEvent: Hashable, Sendable {
    // User intents
    case start
    case pause
    case resume
    case save
    case stop
    case discardSavedState
    // Engine callbacks
    case didStart
    case didPause
    case didResume
    case didSave
    case didStop
    case didFail(VirtualMachineFailure)
}

/// Why a machine stopped unexpectedly. Kept structured so the UI can offer a specific fix.
public enum VirtualMachineFailure: Hashable, Sendable {
    case invalidConfiguration
    case guestCrashed
    case hostOutOfMemory
    case diskImageMissing
    case concurrencyLimitReached(GuestOperatingSystem)
    case engineError(description: String)
}
