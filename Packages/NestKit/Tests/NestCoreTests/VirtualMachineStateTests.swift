// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Testing
@testable import NestCore

@Suite("VirtualMachineState")
struct VirtualMachineStateTests {
    @Test("a full boot → pause → resume → stop cycle")
    func happyPath() throws {
        var state = VirtualMachineState.stopped
        for (event, expected) in [
            (VirtualMachineEvent.start, VirtualMachineState.starting),
            (.didStart, .running),
            (.pause, .pausing),
            (.didPause, .paused),
            (.resume, .resuming),
            (.didResume, .running),
            (.stop, .stopping),
            (.didStop, .stopped),
        ] {
            state = try #require(state.applying(event), "\(event) should be allowed in \(state)")
            #expect(state == expected)
        }
    }

    @Test("saving suspends, starting a suspended machine restores it")
    func suspendAndRestore() throws {
        let saving = try #require(VirtualMachineState.running.applying(.save))
        let suspended = try #require(saving.applying(.didSave))
        #expect(suspended == .suspended)
        #expect(suspended.applying(.start) == .restoring)
        #expect(suspended.applying(.discardSavedState) == .stopped)
    }

    @Test("impossible transitions are rejected", arguments: [
        (VirtualMachineState.stopped, VirtualMachineEvent.pause),
        (.stopped, .stop),
        (.running, .start),
        (.paused, .pause),
        (.suspended, .resume),
        (.stopped, .didFail(.guestCrashed)),
    ])
    func rejected(state: VirtualMachineState, event: VirtualMachineEvent) {
        #expect(state.applying(event) == nil)
    }

    @Test("failures from an active state are recorded and can be restarted")
    func failure() throws {
        let failed = try #require(VirtualMachineState.running.applying(.didFail(.hostOutOfMemory)))
        #expect(failed == .failed(.hostOutOfMemory))
        #expect(failed.applying(.start) == .starting)
    }

    @Test("only stopped or failed machines can be reconfigured")
    func configurationLock() {
        #expect(VirtualMachineState.stopped.allowsConfigurationChanges)
        #expect(VirtualMachineState.failed(.guestCrashed).allowsConfigurationChanges)
        #expect(!VirtualMachineState.running.allowsConfigurationChanges)
        #expect(!VirtualMachineState.suspended.allowsConfigurationChanges)
    }

    @Test("transitional states report progress")
    func transitioning() {
        #expect(VirtualMachineState.starting.isTransitioning)
        #expect(!VirtualMachineState.running.isTransitioning)
        #expect(VirtualMachineState.running.isActive)
        #expect(!VirtualMachineState.suspended.isActive)
    }
}
