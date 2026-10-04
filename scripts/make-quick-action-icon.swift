#!/usr/bin/env swift
// Draws the Quick Action's icon, the menu-bar icon's idle glyph, into the extension's asset
// catalog: `QuickAction/Assets.xcassets/QuickActionIcon.imageset`.
//
// Run from the repository root after changing the glyph: `swift scripts/make-quick-action-icon.swift`
//
// The glyph is the `isIdle` branch of `design/prototype/MenuBarIcon.dc.html`: an 18 × 18 viewBox,
// stroke 1.5, round caps and joins. Finder's Quick Actions menu shows it at 15 pt (the prototype's
// context menu), so it's drawn 15 pt wide, centred in the 16 pt image the menu expects.
//
// Not a template image, although Apple's documentation for `NSExtensionServiceFinderPreviewIconName`
// asks for one: the icon reaches Finder through IconServices, which drops template rendering, so a
// template comes out black in dark mode too. Instead there's a light and a dark variant, each in
// the label colour of that appearance. Bitmaps at exactly 16 pt @1x and @2x, because IconServices
// crops a larger image instead of scaling it. See `docs/quick-action.md`.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let imageSet = URL(fileURLWithPath: "QuickAction/Assets.xcassets/QuickActionIcon.imageset", isDirectory: true)
let canvas: CGFloat = 16
let glyph: CGFloat = 15

/// The glyph's outline in viewBox units, y down as in the SVG.
func glyphPath() -> CGPath {
    let path = CGMutablePath()
    // <rect x="2" y="3" width="14" height="3.75" rx="1">: the lid.
    path.addRoundedRect(in: CGRect(x: 2, y: 3, width: 14, height: 3.75), cornerWidth: 1, cornerHeight: 1)
    // <path d="M3.25 6.75V13.5a1.75 1.75 0 0 0 1.75 1.75h8a1.75 1.75 0 0 0 1.75-1.75V6.75">: the box.
    path.move(to: CGPoint(x: 3.25, y: 6.75))
    path.addLine(to: CGPoint(x: 3.25, y: 13.5))
    path.addArc(tangent1End: CGPoint(x: 3.25, y: 15.25), tangent2End: CGPoint(x: 5, y: 15.25), radius: 1.75)
    path.addLine(to: CGPoint(x: 13, y: 15.25))
    path.addArc(tangent1End: CGPoint(x: 14.75, y: 15.25), tangent2End: CGPoint(x: 14.75, y: 13.5), radius: 1.75)
    path.addLine(to: CGPoint(x: 14.75, y: 6.75))
    // <path d="M9 13V9.4M7.2 11.1L9 9.3l1.8 1.8">: the up arrow.
    path.move(to: CGPoint(x: 9, y: 13))
    path.addLine(to: CGPoint(x: 9, y: 9.4))
    path.move(to: CGPoint(x: 7.2, y: 11.1))
    path.addLine(to: CGPoint(x: 9, y: 9.3))
    path.addLine(to: CGPoint(x: 10.8, y: 11.1))
    return path
}

/// One PNG: the glyph stroked in `white` (0 black, 1 white) at 85 % opacity, the system label colour.
func png(scale: Int, white: CGFloat) throws -> Data {
    let pixels = Int(canvas) * scale
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.featureUnsupported) }
    let unit = glyph / 18 * CGFloat(scale)
    let inset = (canvas - glyph) / 2 * CGFloat(scale)
    // Flip to the SVG's y-down coordinates, then map the viewBox onto the glyph's square.
    context.translateBy(x: inset, y: CGFloat(pixels) - inset)
    context.scaleBy(x: unit, y: -unit)
    context.setLineWidth(1.5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(CGColor(srgbRed: white, green: white, blue: white, alpha: 0.85))
    context.addPath(glyphPath())
    context.strokePath()

    let data = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.featureUnsupported) }
    let dpi = 72 * scale
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

let variants: [(file: String, scale: Int, white: CGFloat, dark: Bool)] = [
    ("QuickActionIcon.png", 1, 0, false),
    ("QuickActionIcon@2x.png", 2, 0, false),
    ("QuickActionIcon-dark.png", 1, 1, true),
    ("QuickActionIcon-dark@2x.png", 2, 1, true),
]

try FileManager.default.createDirectory(at: imageSet, withIntermediateDirectories: true)
var images: [[String: Any]] = []
for variant in variants {
    try png(scale: variant.scale, white: variant.white).write(to: imageSet.appendingPathComponent(variant.file))
    var entry: [String: Any] = ["filename": variant.file, "idiom": "universal", "scale": "\(variant.scale)x"]
    if variant.dark {
        entry["appearances"] = [["appearance": "luminosity", "value": "dark"]]
    }
    images.append(entry)
}
let info = ["author": "xcode", "version": 1] as [String: Any]
let json: [String: Any] = ["images": images, "info": info]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    .write(to: imageSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: imageSet.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Wrote \(imageSet.path)")
