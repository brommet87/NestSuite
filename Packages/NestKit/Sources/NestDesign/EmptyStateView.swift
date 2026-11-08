// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import SwiftUI

/// A centered illustration, headline, explanation and one primary action.
///
/// Every empty screen in NestSuite uses this component, so users always learn *why* a screen is
/// empty and *what to do next*. Guidelines: `docs/design/COMPONENTS.md#empty-state`.
public struct EmptyStateView<Illustration: View, Actions: View>: View {
    private let title: Text
    private let message: Text
    private let illustration: Illustration
    private let actions: Actions

    public init(
        title: Text,
        message: Text,
        @ViewBuilder illustration: () -> Illustration,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.illustration = illustration()
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Tokens.Spacing.large) {
            illustration
                .frame(width: Tokens.Size.heroIllustration, height: Tokens.Size.heroIllustration)
                .padding(.bottom, Tokens.Spacing.small)
            VStack(spacing: Tokens.Spacing.small) {
                title
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                message
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Tokens.Size.readableWidth)
            actions
                .controlSize(.large)
                .padding(.top, Tokens.Spacing.small)
        }
        .padding(Tokens.Spacing.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Empty state") {
    EmptyStateView(
        title: Text(verbatim: "No Virtual Machines"),
        message: Text(verbatim: "Create a virtual machine to run Linux or macOS alongside your Mac apps.")
    ) {
        BrandMark()
    } actions: {
        Button(String("New Virtual Machine…")) {}
            .buttonStyle(.borderedProminent)
    }
    .frame(width: 640, height: 480)
}
