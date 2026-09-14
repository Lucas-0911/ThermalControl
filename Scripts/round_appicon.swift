#!/usr/bin/swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
let srcPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/tmp/tc-icon-src.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("cannot read \(srcPath)\n", stderr)
    exit(1)
}

let size = 1024
let radius = CGFloat(size) * 0.223 // ~228px, iOS/mac rounded-square
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                        xRadius: radius, yRadius: radius)
path.addClip()
src.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
         from: .zero, operation: .copy, fraction: 1)
img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }

let master = URL(fileURLWithPath: "/tmp/tc-icon-round-1024.png")
try png.write(to: master)

let iconset = URL(fileURLWithPath: "/tmp/ThermalAppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

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
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path]
    try p.run()
    p.waitUntilExit()
    let dest = catalog.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.copyItem(at: iconset.appendingPathComponent(name), to: dest)
}

let icns = root.appendingPathComponent("App/Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: icns.deletingLastPathComponent(), withIntermediateDirectories: true)
let iu = Process()
iu.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iu.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iu.run()
iu.waitUntilExit()
print("ok \(icns.path)")
