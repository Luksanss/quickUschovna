// Writes the disk image's background: design/dmg/background.png and background@2x.png.
//
//     xcrun swift design/dmg/make-background.swift
//
// dmgbuild merges the pair into one HiDPI TIFF (scripts/dmg-settings.py). Finder pins the picture
// to the top left of the window's content, which is the window minus its 32 pt title bar, so the
// last 32 pt of the canvas are bleed and stay empty. Coordinates are points from the top left,
// like dmgbuild's icon_locations: change a position here and there together.
import AppKit

let canvas = CGSize(width: 640, height: 400)
let appIcon = CGPoint(x: 180, y: 196) // icon centres, as in scripts/dmg-settings.py
let applications = CGPoint(x: 460, y: 196)
let headlineY = 68.0

// The parcel from design/icon/make-icon.swift, on its 1024-point canvas: lid, body and arrow.
let lid = (x: 228.0, y: 248.0, w: 568.0, h: 148.0, radius: 48.0)
let body = (x: 272.0, y: 432.0, w: 480.0, h: 352.0, top: 20.0, bottom: 76.0)
let arrow = (tip: 506.0, tail: 714.0, reach: 106.0, stroke: 78.0)
let brand = NSColor(srgbRed: 0.04, green: 0.60, blue: 0.52, alpha: 1)
let ink = NSColor(srgbRed: 0.07, green: 0.16, blue: 0.16, alpha: 1)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
}

// The parcel's full extent on the icon's canvas, from the lid's top left to the body's bottom.
let parcel = CGRect(x: lid.x, y: lid.y, width: lid.w, height: body.y + body.h - lid.y)

func parcelWidth(height: CGFloat) -> CGFloat { height * parcel.width / parcel.height }

// A rectangle with one radius for its top corners and another for its bottom ones, top-left points.
func roundedRect(_ r: CGRect, top t: CGFloat, bottom b: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: r.minX + t, y: r.minY))
    path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: t)
    path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: b)
    path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: b)
    path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: t)
    path.closeSubpath()
    return path
}

// A parcel `height` tall with its top left at `origin`: a light teal lid, a white body, and the
// arrow in teal, as in the light app icon.
func drawParcel(origin: CGPoint, height: CGFloat, in ctx: CGContext) {
    let k = height / parcel.height
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: origin.x + (x - parcel.minX) * k, y: origin.y + (y - parcel.minY) * k, width: w * k, height: h * k)
    }
    let lidRect = rect(lid.x, lid.y, lid.w, lid.h), bodyRect = rect(body.x, body.y, body.w, body.h)
    ctx.saveGState()
    // A shadow's offset and blur are in device pixels, y up, whatever the transform: scale them,
    // and point the offset down.
    let scale = hypot(ctx.ctm.a, ctx.ctm.b)
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.08 * scale), blur: height * 0.30 * scale,
                  color: brand.withAlphaComponent(0.30).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(roundedRect(lidRect, top: lid.radius * k, bottom: lid.radius * k))
    ctx.setFillColor(brand.blended(withFraction: 0.55, of: .white)!.cgColor)
    ctx.fillPath()
    ctx.addPath(roundedRect(bodyRect, top: body.top * k, bottom: body.bottom * k))
    ctx.setFillColor(.white)
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    let cx = bodyRect.midX
    let tip = CGPoint(x: cx, y: origin.y + (arrow.tip - parcel.minY) * k)
    let reach = arrow.reach * k
    ctx.move(to: CGPoint(x: cx, y: origin.y + (arrow.tail - parcel.minY) * k))
    ctx.addLine(to: tip)
    ctx.move(to: CGPoint(x: cx - reach, y: tip.y + reach))
    ctx.addLine(to: tip)
    ctx.addLine(to: CGPoint(x: cx + reach, y: tip.y + reach))
    ctx.setStrokeColor(brand.cgColor)
    ctx.setLineWidth(arrow.stroke * k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

// Parcels drifting at the edges at different depths: (centre, height, degrees of tilt, opacity).
let drifting: [(CGPoint, CGFloat, CGFloat, CGFloat)] = [
    (CGPoint(x: 62, y: 74), 44, -12, 0.55),
    (CGPoint(x: 32, y: 198), 24, 16, 0.30),
    (CGPoint(x: 90, y: 316), 32, 8, 0.40),
    (CGPoint(x: 580, y: 66), 38, 14, 0.50),
    (CGPoint(x: 610, y: 188), 22, -18, 0.28),
    (CGPoint(x: 560, y: 312), 30, -8, 0.38),
]

func draw(in ctx: CGContext) {
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

    // A cool white, turning a little teal towards the bottom, with a teal glow behind the icons.
    let wash = CGGradient(colorsSpace: rgb, colors: [
        CGColor(srgbRed: 0.988, green: 0.996, blue: 0.996, alpha: 1),
        CGColor(srgbRed: 0.918, green: 0.973, blue: 0.965, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(wash, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
    let glow = CGGradient(colorsSpace: rgb, colors: [
        brand.withAlphaComponent(0.13).cgColor, brand.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    let middle = CGPoint(x: canvas.width / 2, y: appIcon.y)
    ctx.drawRadialGradient(glow, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: 300, options: [])

    // A faint dot grid that fades out towards the middle, so the icons sit on a clean field.
    ctx.saveGState()
    for x in stride(from: 8.0, to: canvas.width, by: 16) {
        for y in stride(from: 8.0, to: canvas.height, by: 16) {
            let d = hypot((x - middle.x) / 320, (y - middle.y) / 200)
            let alpha = max(0, min(1, (d - 0.55) / 0.6)) * 0.16
            guard alpha > 0.005 else { continue }
            ctx.setFillColor(brand.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
        }
    }
    ctx.restoreGState()

    for (centre, height, tilt, opacity) in drifting {
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: tilt * .pi / 180)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawParcel(origin: CGPoint(x: -parcelWidth(height: height) / 2, y: -height / 2), height: height, in: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // The headline: "Drag. Drop." and then a parcel, what the app sends.
    let words = NSAttributedString(string: "Drag. Drop.", attributes: [
        .font: rounded(30, .bold), .foregroundColor: ink, .kern: -0.3,
    ])
    let parcelHeight = 34.0, gap = 14.0
    let width = words.size().width + gap + parcelWidth(height: parcelHeight)
    let x = (canvas.width - width) / 2
    words.draw(at: CGPoint(x: x, y: headlineY - words.size().height / 2))
    drawParcel(origin: CGPoint(x: x + words.size().width + gap, y: headlineY - parcelHeight / 2 - 1),
               height: parcelHeight, in: ctx)

    // The arrow: a hop from the app that lands level at Applications, dots growing into a chevron.
    let from = CGPoint(x: appIcon.x + 84, y: appIcon.y), to = CGPoint(x: applications.x - 80, y: applications.y)
    let rise = CGPoint(x: from.x + 36, y: from.y - 36), land = CGPoint(x: to.x - 46, y: to.y)
    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * from.x + b * rise.x + c * land.x + d * to.x,
                       y: a * from.y + b * rise.y + c * land.y + d * to.y)
    }
    let dots = 10
    for i in 0..<dots {
        let t = 0.84 * CGFloat(i) / CGFloat(dots - 1)
        let p = point(t), r = 1.5 + 1.8 * t
        ctx.setFillColor(brand.withAlphaComponent(0.22 + 0.78 * t).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.move(to: CGPoint(x: to.x - 9, y: to.y - 10))
    ctx.addLine(to: to)
    ctx.addLine(to: CGPoint(x: to.x - 9, y: to.y + 10))
    ctx.setStrokeColor(brand.cgColor)
    ctx.setLineWidth(4.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func render(scale: CGFloat, to url: URL) throws {
    let ctx = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip to top-left points, like Finder's.
    ctx.translateBy(x: 0, y: canvas.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(in: ctx)
    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = canvas // 72 dpi at 1x, 144 at 2x, which tiffutil needs to pair them
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
try render(scale: 1, to: folder.appendingPathComponent("background.png"))
try render(scale: 2, to: folder.appendingPathComponent("background@2x.png"))
