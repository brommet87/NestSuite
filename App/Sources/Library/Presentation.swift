// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import Foundation
import NestCore

// Localized, user-facing text for domain values. NestCore stays free of UI strings; the app owns
// the wording (see docs/design/VOICE-AND-TONE.md).

extension NetworkMode {
    var localizedName: LocalizedStringResource {
        switch self {
        case .nat: "Shared with Mac"
        case .disconnected: "Disconnected"
        }
    }
}

extension ConfigurationIssue {
    var localizedDescription: String {
        switch self {
        case .emptyName:
            String(localized: "Enter a name for the virtual machine.")
        case let .nameTooLong(maximum):
            String(localized: "Use a name with at most \(maximum) characters.")
        case let .cpuCountOutOfRange(allowed):
            String(localized: "Choose between \(allowed.lowerBound) and \(allowed.upperBound) processors.")
        case let .memoryOutOfRange(minimum, maximum):
            String(localized: "Choose between \(minimum.description) and \(maximum.description) of memory.")
        case let .memoryLeavesTooLittleForHost(recommendedMaximum):
            String(localized: "Your Mac may become slow. Consider at most \(recommendedMaximum.description) of memory.")
        case let .diskTooSmall(minimum):
            String(localized: "The disk needs at least \(minimum.description).")
        case .rosettaUnsupportedForGuest:
            String(localized: "Rosetta is only available for Linux.")
        case .rosettaUnavailableOnHost:
            String(localized: "Rosetta isn’t installed on this Mac.")
        case .macOSGuestsUnsupportedOnHost:
            String(localized: "macOS virtual machines require a Mac with Apple silicon.")
        case let .duplicateSharedFolderName(name):
            String(localized: "Two shared folders are named “\(name)”. Give each a unique name.")
        case let .unsupportedSchemaVersion(found, supported):
            String(
                // Localization key: kept on one line so it matches the string catalog.
                // swiftlint:disable:next line_length
                localized: "Created with a newer NestSuite (format \(found), this version reads \(supported)). Update NestSuite to open it."
            )
        }
    }
}

extension VirtualMachineLibraryError {
    /// A localized, actionable explanation for the user.
    var userMessage: String {
        switch self {
        case .configurationMissing:
            String(localized: "The settings file (config.json) is missing from this virtual machine.")
        case let .configurationUnreadable(_, reason):
            String(localized: "The settings file is damaged and can’t be read. Details: \(reason)")
        case let .unsupportedSchemaVersion(found, supported):
            String(
                // Localization key: kept on one line so it matches the string catalog.
                // swiftlint:disable:next line_length
                localized: "Created with a newer NestSuite (format \(found), this version reads \(supported)). Update NestSuite to open it."
            )
        case .bundleAlreadyExists:
            String(localized: "A virtual machine with this name already exists.")
        }
    }
}
