// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 NestSuite contributors

//
// Renders the NestSuite app icon (1024 × 1024 PNG) from code, after the brand logo in Design/Brand.
// Usage: swift Scripts/render-app-icon.swift <output.png>
// Called by Scripts/render-app-icon.sh, which also produces all required sizes.

import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let cyan = color(0x22C6F5), azure = color(0x3D8BEF), indigo = color(0x4338CA), violet = color(0x8B3FE0)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

guard let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create bitmap context") }

func gradient(_ colors: [CGColor]) -> CGGradient {
    let locations = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// 1. Tile: macOS icon grid — 824 pt rounded square centered on a 1024 canvas.
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
context.addPath(tile)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
context.drawLinearGradient(
    gradient([color(0xFFFFFF), color(0xEEF2FB)]),
    start: CGPoint(x: 512, y: tileRect.maxY), end: CGPoint(x: 512, y: tileRect.minY), options: []
)
context.restoreGState()

/// 2. Nest layers: rounded rhombi (squares rotated 45° and squashed vertically).
func rhombus(centerY: CGFloat) -> CGPath {
    let side: CGFloat = 430
    var transform = CGAffineTransform(translationX: 512, y: centerY)
        .scaledBy(x: 1, y: 0.62)
        .rotated(by: .pi / 4)
        .translatedBy(x: -side / 2, y: -side / 2)
    return CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
        cornerWidth: 92, cornerHeight: 92, transform: &transform
    )
}

let lower = rhombus(centerY: 440)
context.saveGState()
context.addPath(lower)
context.clip()
context.drawLinearGradient(
    gradient([violet, indigo]), start: CGPoint(x: 230, y: 440), end: CGPoint(x: 800, y: 440), options: []
)
context.restoreGState()

let upper = rhombus(centerY: 555)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x3B2FB0, 0.45))
context.addPath(upper)
context.setFillColor(azure)
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(upper)
context.clip()
context.drawLinearGradient(
    gradient([cyan, azure, indigo]), start: CGPoint(x: 760, y: 760), end: CGPoint(x: 260, y: 360), options: []
)
context.restoreGState()

// 3. Display glyph: neutral monitor outline in white.
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(30)
context.setLineCap(.round)
context.setLineJoin(.round)
let screen = CGRect(x: 420, y: 528, width: 184, height: 124)
context.addPath(CGPath(roundedRect: screen, cornerWidth: 26, cornerHeight: 26, transform: nil))
context.strokePath()
context.move(to: CGPoint(x: 512, y: 528))
context.addLine(to: CGPoint(x: 512, y: 484))
context.move(to: CGPoint(x: 470, y: 484))
context.addLine(to: CGPoint(x: 554, y: 484))
context.strokePath()

guard let image = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("Could not encode PNG") }
try data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
