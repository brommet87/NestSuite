// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import SwiftUI

/// Design tokens: the only place raw design values live.
///
/// Views use these tokens, never literal numbers or hex colors, so the visual language stays
/// consistent and can change in one place. Values and rationale: `docs/design/TOKENS.md`.
public enum Tokens {}

// MARK: - Color

public extension Tokens {
    /// Brand colors sampled from the NestSuite logo. Use for accents and illustrations only —
    /// text and surfaces use semantic system colors so Dark Mode and Increase Contrast work.
    enum Brand {
        public static let cyan = Color(red: 0x22 / 255, green: 0xC6 / 255, blue: 0xF5 / 255)
        public static let azure = Color(red: 0x3D / 255, green: 0x8B / 255, blue: 0xEF / 255)
        public static let indigo = Color(red: 0x43 / 255, green: 0x38 / 255, blue: 0xCA / 255)
        public static let violet = Color(red: 0x8B / 255, green: 0x3F / 255, blue: 0xE0 / 255)
        public static let ink = Color(red: 0x0A / 255, green: 0x0E / 255, blue: 0x1A / 255)

        /// The signature gradient of the logo mark (top-left cyan → bottom-right violet).
        public static let gradient = LinearGradient(
            colors: [cyan, azure, indigo, violet],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    /// Colors with meaning. Every status is also conveyed by an SF Symbol and text, never by color alone.
    enum Status {
        public static let running = Color.green
        public static let paused = Color.orange
        public static let suspended = Color.indigo
        public static let stopped = Color.secondary
        public static let failed = Color.red
        public static let transitioning = Color.accentColor
    }
}

// MARK: - Spacing (4-pt grid)

public extension Tokens {
    enum Spacing {
        public static let xxSmall: CGFloat = 2
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let xLarge: CGFloat = 24
        public static let xxLarge: CGFloat = 32
        public static let xxxLarge: CGFloat = 48
    }
}

// MARK: - Shape

public extension Tokens {
    enum Radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
        public static let large: CGFloat = 14
        public static let xLarge: CGFloat = 20
    }
}

// MARK: - Size

public extension Tokens {
    enum Size {
        /// Minimum hit target for custom controls (Apple HIG for macOS pointer targets).
        public static let minimumHitTarget: CGFloat = 28
        public static let sidebarIcon: CGFloat = 28
        public static let heroIllustration: CGFloat = 96
        /// Comfortable reading width for body text in empty states and sheets.
        public static let readableWidth: CGFloat = 420
    }
}

// MARK: - Motion

public extension Tokens {
    enum Motion {
        /// Standard UI response. Use with `.animation(Tokens.Motion.standard(reduceMotion:), value:)`.
        public static func standard(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .snappy(duration: 0.25)
        }
    }
}
