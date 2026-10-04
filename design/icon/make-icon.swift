// Writes quickUschovna/AppIcon.icon, the app icon: a parcel with an up arrow, the menu-bar glyph
// drawn bold.
//
//     xcrun swift design/icon/make-icon.swift [output.icon]
//
// The icon is an Icon Composer document: icon.json plus one SVG per layer. Xcode's actool turns it
// into Assets.car and AppIcon.icns, with the light, dark, tinted and clear looks.
import Foundation

// On Icon Composer's 1024-point canvas: the parcel's lid, its body (narrower, a gap below the lid,
// with tight corners at the top and round ones at the bottom), and the arrow on the body: where its
// tip and tail are, how far its arms reach, and its line width.
let lid = (x: 228.0, y: 248.0, w: 568.0, h: 148.0, radius: 48.0)
let body = (x: 272.0, y: 432.0, w: 480.0, h: 352.0, top: 20.0, bottom: 76.0)
let arrow = (tip: 506.0, tail: 714.0, reach: 106.0, stroke: 78.0)
let brand = "extended-srgb:0.04000,0.60000,0.52000,1.00000" // teal green

func n(_ v: Double) -> String {
    let rounded = (v * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
}

// A rectangle with one radius for its top corners and another for its bottom ones.
func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, top t: Double, bottom b: Double) -> String {
    let arc = { (r: Double, x: Double, y: Double) in "A\(n(r)),\(n(r)) 0 0 1 \(n(x)),\(n(y))" }
    return [
        "M\(n(x + t)),\(n(y)) H\(n(x + w - t))", arc(t, x + w, y + t),
        "V\(n(y + h - b))", arc(b, x + w - b, y + h),
        "H\(n(x + b))", arc(b, x, y + h - b),
        "V\(n(y + t))", arc(t, x + t, y), "Z",
    ].joined(separator: " ")
}

// A line with round ends, as a filled shape: actool fills the layer's paths, and a stroked path
// would lose its width.
func capsule(_ a: (Double, Double), _ b: (Double, Double), radius r: Double) -> String {
    let length = hypot(b.0 - a.0, b.1 - a.1)
    let normal = (-(b.1 - a.1) / length * r, (b.0 - a.0) / length * r)
    let point = { (p: (Double, Double), sign: Double) in "\(n(p.0 + sign * normal.0)),\(n(p.1 + sign * normal.1))" }
    let arc = "A\(n(r)),\(n(r)) 0 0 0"
    return "M\(point(a, 1)) L\(point(b, 1)) \(arc) \(point(b, -1)) L\(point(a, -1)) \(arc) \(point(a, 1)) Z"
}

// The up arrow, centred on the body: a shaft and two arms meeting at the tip, at 45 degrees.
func upArrow() -> [String] {
    let cx = body.x + body.w / 2, r = arrow.stroke / 2
    let tip = (cx, arrow.tip)
    return [
        capsule((cx, arrow.tail), tip, radius: r),
        capsule(tip, (cx - arrow.reach, arrow.tip + arrow.reach), radius: r),
        capsule(tip, (cx + arrow.reach, arrow.tip + arrow.reach), radius: r),
    ]
}

func svg(_ element: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      \(element)
    </svg>

    """
}

let svgs = [
    "lid": svg("<path fill=\"#FFFFFF\" d=\"\(roundedRect(lid.x, lid.y, lid.w, lid.h, top: lid.radius, bottom: lid.radius))\"/>"),
    "body": svg("<path fill=\"#FFFFFF\" d=\"\(roundedRect(body.x, body.y, body.w, body.h, top: body.top, bottom: body.bottom))\"/>"),
    // One path per capsule, so where they overlap they add up whatever the fill rule.
    "arrow": svg(upArrow().map { "<path fill=\"#FFFFFF\" d=\"\($0)\"/>" }.joined(separator: "\n  ")),
]

func solid(_ light: String, dark: String) -> [[String: Any]] {
    [["value": ["solid": light]], ["appearance": "dark", "value": ["solid": dark]]]
}

func layer(_ name: String, glass: Bool, fill: [[String: Any]], opacity: String? = nil) -> [String: Any] {
    var layer: [String: Any] = ["name": name, "image-name": "\(name).svg", "glass": glass, "fill-specializations": fill]
    if let opacity { layer["opacity"] = NSDecimalNumber(string: opacity) }
    return layer
}

func group(_ name: String, _ layers: [[String: Any]], shadow: String) -> [String: Any] {
    ["name": name, "layers": layers, "shadow": ["kind": shadow, "opacity": 0.5], "translucency": ["enabled": false, "value": 0.5]]
}

// Light: a white parcel with a teal arrow on a teal gradient. Dark: a grey parcel with a white arrow
// on the system's dark background. The first group is drawn on top. The system derives the tinted
// and clear looks.
let white = "extended-srgb:1.00000,1.00000,1.00000,1.00000"
let icon: [String: Any] = [
    "fill-specializations": [
        ["value": ["automatic-gradient": brand]],
        ["appearance": "dark", "value": "automatic"],
    ],
    "groups": [
        group("Arrow", [layer("arrow", glass: false, fill: solid(brand, dark: white))], shadow: "none"),
        group("Parcel", [
            layer("lid", glass: true, fill: solid(white, dark: "extended-gray:0.40000,1.00000")),
            layer("body", glass: true, fill: solid(white, dark: "extended-gray:0.30000,1.00000")),
        ], shadow: "neutral"),
    ],
    "supported-platforms": ["squares": ["macOS"]],
]

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repo.appendingPathComponent("quickUschovna/AppIcon.icon")
precondition(output.pathExtension == "icon", "the output must be a .icon bundle, since it is replaced")
let assets = output.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
for (name, contents) in svgs {
    try contents.write(to: assets.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
}
let json = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (json + Data("\n".utf8)).write(to: output.appendingPathComponent("icon.json"))
print("wrote \(output.path)")
