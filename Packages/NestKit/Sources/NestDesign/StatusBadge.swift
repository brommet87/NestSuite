// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import NestCore
import SwiftUI

/// Shows a VM's lifecycle state with symbol, color and text together.
///
/// Color is never the only signal (WCAG 1.4.1): each state has its own SF Symbol, and the text is
/// read by VoiceOver.
public struct StatusBadge: View {
    private let state: VirtualMachineState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: VirtualMachineState) {
        self.state = state
    }

    public var body: some View {
        Label {
            Text(state.localizedTitle)
        } icon: {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: state.isTransitioning && !reduceMotion)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

public extension VirtualMachineState {
    /// The SF Symbol for this state.
    var symbolName: String {
        switch self {
        case .stopped: "stop.circle"
        case .starting, .restoring, .resuming: "play.circle"
        case .running: "play.circle.fill"
        case .pausing, .paused: "pause.circle.fill"
        case .saving, .suspended: "moon.circle.fill"
        case .stopping: "stop.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// The semantic tint for this state.
    var tint: Color {
        switch self {
        case .running: Tokens.Status.running
        case .paused: Tokens.Status.paused
        case .suspended: Tokens.Status.suspended
        case .stopped: Tokens.Status.stopped
        case .failed: Tokens.Status.failed
        case .starting, .pausing, .resuming, .saving, .restoring, .stopping: Tokens.Status.transitioning
        }
    }

    /// A short, localized title such as "Running".
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .stopped: LocalizedStringResource("Stopped", bundle: .atURL(Bundle.module.bundleURL))
        case .starting: LocalizedStringResource("Starting…", bundle: .atURL(Bundle.module.bundleURL))
        case .running: LocalizedStringResource("Running", bundle: .atURL(Bundle.module.bundleURL))
        case .pausing: LocalizedStringResource("Pausing…", bundle: .atURL(Bundle.module.bundleURL))
        case .paused: LocalizedStringResource("Paused", bundle: .atURL(Bundle.module.bundleURL))
        case .resuming: LocalizedStringResource("Resuming…", bundle: .atURL(Bundle.module.bundleURL))
        case .saving: LocalizedStringResource("Saving State…", bundle: .atURL(Bundle.module.bundleURL))
        case .suspended: LocalizedStringResource("Suspended", bundle: .atURL(Bundle.module.bundleURL))
        case .restoring: LocalizedStringResource("Restoring…", bundle: .atURL(Bundle.module.bundleURL))
        case .stopping: LocalizedStringResource("Shutting Down…", bundle: .atURL(Bundle.module.bundleURL))
        case .failed: LocalizedStringResource("Stopped Unexpectedly", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}

#Preview("All states") {
    let states: [VirtualMachineState] = [
        .stopped, .starting, .running, .paused, .saving, .suspended, .stopping, .failed(.guestCrashed),
    ]
    VStack(alignment: .leading, spacing: Tokens.Spacing.small) {
        ForEach(states, id: \.self) { StatusBadge(state: $0) }
    }
    .padding(Tokens.Spacing.xLarge)
}
