#!/usr/bin/swift
// Generates the Thermal Control app icon: a white swept-blade fan with a
// bolt badge on a cool blue→teal squircle, drawn per the macOS icon grid
// (1024 canvas, 824 body, ~185 corner radius). Writes the asset-catalog
// PNG set + AppIcon.icns. Run: swift Scripts/generate_appicon.swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)

let S: CGFloat = 1024 // canvas
let body: CGFloat = 824
let inset = (S - body) / 2
let corner: CGFloat = 185

func makeContext(_ size: CGFloat) -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
        bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

let ctx = makeContext(S)

// ── Squircle body with vertical gradient (sky → deep blue) ──────────────
let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)
let bodyPath = CGPath(
    roundedRect: bodyRect, cornerWidth: corner, cornerHeight: corner, transform: nil
)
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let bg = CGGradient(
    colorsSpace: nil,
    colors: [color(0x14B8E6), color(0x0E72C9), color(0x123C8C)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
    bg, start: CGPoint(x: S * 0.2, y: S), end: CGPoint(x: S * 0.8, y: 0),
    options: []
)
// glass highlight top-left
let hl = CGGradient(
    colorsSpace: nil,
    colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    hl, startCenter: CGPoint(x: S * 0.32, y: S * 0.82), startRadius: 0,
    endCenter: CGPoint(x: S * 0.32, y: S * 0.82), endRadius: S * 0.6, options: []
)
ctx.restoreGState()

// ── Fan: 4 tapered swept blades + hub ────────────────────────────────────
// Positioned slightly up-left so the bolt badge (bottom-right) never
// overlaps a blade tip.
let fanC = CGPoint(x: S / 2 - 26, y: S / 2 + 34)
let hubR: CGFloat = 58
let bladeR: CGFloat = 228

func polar(_ deg: CGFloat, _ r: CGFloat, origin: CGPoint = fanC) -> CGPoint {
    let a = deg * .pi / 180
    return CGPoint(x: origin.x + cos(a) * r, y: origin.y + sin(a) * r)
}

// Note: CG y-up is flipped when the bitmap renders top-down; we draw with
// y-up math and rely on the standard CGContext orientation (y up), so
// angles run counter-clockwise visually.
func bladePath() -> CGMutablePath {
    let p = CGMutablePath()
    // Narrow scythe-like blade: ~55° angular span at the hub tapering to a
    // rounded point at the tip (previous 76° span rendered as fat blobs).
    p.move(to: polar(98, hubR * 0.9))
    p.addCurve(
        to: polar(44, bladeR),
        control1: polar(122, bladeR * 0.52),
        control2: polar(84, bladeR * 0.98)
    )
    // rounded tip
    p.addQuadCurve(to: polar(30, bladeR * 0.82), control: polar(39, bladeR * 1.06))
    // concave inner edge back to hub
    p.addCurve(
        to: polar(62, hubR * 0.9),
        control1: polar(16, bladeR * 0.48),
        control2: polar(38, hubR * 1.9)
    )
    p.closeSubpath()
    return p
}

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
// soft shadow under the fan
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x04203F, 0.32))
for i in 0..<4 {
    ctx.saveGState()
    ctx.translateBy(x: fanC.x, y: fanC.y)
    ctx.rotate(by: CGFloat(i) * .pi / 2 + 0.30) // dynamic rotational sweep
    ctx.translateBy(x: -fanC.x, y: -fanC.y)
    ctx.addPath(bladePath())
    ctx.setFillColor(color(0xFFFFFF, 0.97))
    ctx.fillPath()
    ctx.restoreGState()
}
ctx.restoreGState()

// hub
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addEllipse(in: CGRect(x: fanC.x - hubR, y: fanC.y - hubR, width: hubR * 2, height: hubR * 2))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.addEllipse(in: CGRect(x: fanC.x - hubR * 0.42, y: fanC.y - hubR * 0.42, width: hubR * 0.84, height: hubR * 0.84))
ctx.setFillColor(color(0x0E72C9))
ctx.fillPath()

// ── Bolt badge (bottom-right) ────────────────────────────────────────────
let badgeC = CGPoint(x: S / 2 + 224, y: S / 2 - 220) // CG y-up: -220 = lower right
let badgeR: CGFloat = 114

// white ring + dark-blue disc
ctx.addEllipse(in: CGRect(x: badgeC.x - badgeR, y: badgeC.y - badgeR, width: badgeR * 2, height: badgeR * 2))
ctx.setFillColor(color(0xFFFFFF))
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x06264A, 0.5))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
let discR = badgeR - 14
ctx.addEllipse(in: CGRect(x: badgeC.x - discR, y: badgeC.y - discR, width: discR * 2, height: discR * 2))
let disc = CGGradient(
    colorsSpace: nil,
    colors: [color(0x11408F), color(0x0B2A66)] as CFArray, locations: [0, 1]
)!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: badgeC.x - discR, y: badgeC.y - discR, width: discR * 2, height: discR * 2))
ctx.clip()
ctx.drawLinearGradient(disc, start: CGPoint(x: badgeC.x, y: badgeC.y + discR), end: CGPoint(x: badgeC.x, y: badgeC.y - discR), options: [])
ctx.restoreGState()

// lightning bolt (amber gradient), centered in badge
func boltPath() -> CGMutablePath {
    let p = CGMutablePath()
    let h: CGFloat = 84, w: CGFloat = 54 // half extents, fits the disc
    let c = badgeC
    // classic bolt: top-left edge down to middle, jog, then down to tip
    p.move(to: CGPoint(x: c.x + 18, y: c.y + h))          // top
    p.addLine(to: CGPoint(x: c.x - w, y: c.y + 8))        // down-left
    p.addLine(to: CGPoint(x: c.x - 12, y: c.y + 8))       // jog right
    p.addLine(to: CGPoint(x: c.x - 30, y: c.y - h))       // down to tip…
    p.addLine(to: CGPoint(x: c.x + w, y: c.y - 4))        // back up-right
    p.addLine(to: CGPoint(x: c.x + 10, y: c.y - 4))       // jog left
    p.closeSubpath()
    return p
}
ctx.saveGState()
ctx.addPath(boltPath())
ctx.clip()
let boltG = CGGradient(
    colorsSpace: nil,
    colors: [color(0xFFE54C), color(0xFFB800)] as CFArray, locations: [0, 1]
)!
ctx.drawLinearGradient(
    boltG, start: CGPoint(x: badgeC.x, y: badgeC.y + 86),
    end: CGPoint(x: badgeC.x, y: badgeC.y - 86), options: []
)
ctx.restoreGState()

// ── Export master PNG + sizes + icns ─────────────────────────────────────
guard let image = ctx.makeImage() else { fputs("makeImage failed\n", stderr); exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let master = URL(fileURLWithPath: "/tmp/ThermalAppIcon-1024.png")
try png.write(to: master)
print("master: \(master.path)")

let tmp = URL(fileURLWithPath: "/tmp/ThermalAppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
let catalog = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
for (px, name) in sizes {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", tmp.appendingPathComponent(name).path]
    try process.run()
    process.waitUntilExit()
    try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: catalog.appendingPathComponent(name))
    try FileManager.default.copyItem(at: tmp.appendingPathComponent(name), to: catalog.appendingPathComponent(name))
}

let icnsOut = root.appendingPathComponent("App/Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: icnsOut.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", tmp.path, "-o", icnsOut.path]
try iconutil.run()
iconutil.waitUntilExit()
print("wrote \(icnsOut.path)")