// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import AppKit
import NestCore
import NestVirtualization

/// Protects running machines when the app quits: asks first, then shuts guests down cleanly and only
/// powers off what doesn't stop in time. Quitting must never silently pull the plug on a guest.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var library: LibraryModel?
    static let shutdownTimeout: Duration = .seconds(20)

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let running = library?.sessions.values.filter(\.state.isActive) ?? []
        guard !running.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Shut Down Running Virtual Machines?")
        alert.informativeText = String(
            // swiftlint:disable:next line_length
            localized: "\(running.count) virtual machine(s) are running. NestSuite asks each one to shut down before quitting."
        )
        alert.addButton(withTitle: String(localized: "Shut Down and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        Task {
            await Self.shutDown(running)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Requests a clean shutdown of every session, then force-stops the ones still active after the timeout.
    static func shutDown(_ sessions: [VirtualMachineSession]) async {
        for session in sessions where session.state == .running {
            try? session.requestStop()
        }
        let deadline = ContinuousClock.now + shutdownTimeout
        while ContinuousClock.now < deadline, sessions.contains(where: \.state.isActive) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        for session in sessions where session.state.isActive {
            try? await session.forceStop()
        }
    }
}
