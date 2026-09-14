#!/usr/bin/swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let src = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
guard let img = NSImage(contentsOf: src),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    fputs("cannot read \(src.path)\n", stderr)
    exit(1)
}

let w = rep.pixelsWide
let h = rep.pixelsHigh
let teal = rep.colorAt(x: w / 2, y: max(8, h / 12)) ?? NSColor(calibratedRed: 0.17, green: 0.41, blue: 0.39, alpha: 1)

func isCornerWhite(_ c: NSColor) -> Bool {
    let rgb = c.usingColorSpace(.genericRGB) ?? c
    return rgb.redComponent > 0.85 && rgb.greenComponent > 0.85 && rgb.blueComponent > 0.85
}

let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
for y in 0..<h {
    for x in 0..<w {
        let c = rep.colorAt(x: x, y: y) ?? teal
        out.setColor(isCornerWhite(c) ? teal : c, atX: x, y: y)
    }
}

guard let png = out.representation(using: .png, properties: [:]) else { exit(1) }
let tmp = URL(fileURLWithPath: "/tmp/ThermalAppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let master = URL(fileURLWithPath: "/tmp/ThermalAppIcon-1024.png")
try png.write(to: master)

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
    (1024, "icon_512x512@2x.png")
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
