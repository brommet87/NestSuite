// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

import SwiftUI

/// The NestSuite logo mark, drawn in code so it stays sharp at every size and needs no bitmap.
///
/// Two stacked rounded "nest" layers with a display glyph on top, after the brand logo in
/// `Design/Brand`. Decorative by default (hidden from VoiceOver); pass a label when it carries meaning.
public struct BrandMark: View {
    private let accessibilityLabel: Text?

    public init(accessibilityLabel: Text? = nil) {
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                // Three stacked layers, bottom to top, as in the brand logo.
                layer(side: side)
                    .fill(horizontalGradient(Tokens.Brand.violet, Tokens.Brand.indigo))
                    .offset(y: side * 0.24)
                layer(side: side)
                    .fill(horizontalGradient(Tokens.Brand.violet, Tokens.Brand.azure))
                    .shadow(color: Tokens.Brand.indigo.opacity(0.3), radius: side * 0.03, y: side * 0.02)
                    .offset(y: side * 0.11)
                layer(side: side)
                    .fill(Tokens.Brand.gradient)
                    .shadow(color: Tokens.Brand.indigo.opacity(0.35), radius: side * 0.04, y: side * 0.03)
                    .offset(y: -side * 0.03)
                DisplayGlyph()
                    .stroke(.white, style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round, lineJoin: .round))
                    .frame(width: side * 0.26, height: side * 0.22)
                    .offset(y: -side * 0.04)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? Text(verbatim: ""))
    }

    private func horizontalGradient(_ start: Color, _ end: Color) -> LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .leading, endPoint: .trailing)
    }

    /// A rhombus with generously rounded corners.
    private func layer(side: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
            .scale(x: 0.62, y: 0.62)
            .rotation(.degrees(45))
            .scale(x: 1, y: 0.62)
    }
}

/// A simple monitor: rounded screen plus stand. Neutral on purpose — it stands for "any guest OS".
private struct DisplayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let screen = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.72)
        path.addRoundedRect(in: screen, cornerSize: CGSize(width: rect.width * 0.12, height: rect.width * 0.12))
        path.move(to: CGPoint(x: rect.midX, y: screen.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.22, y: rect.maxY))
        return path
    }
}

#Preview("Brand mark") {
    HStack(spacing: Tokens.Spacing.xLarge) {
        BrandMark().frame(width: 32)
        BrandMark().frame(width: 64)
        BrandMark().frame(width: 128)
    }
    .padding(Tokens.Spacing.xxLarge)
}
