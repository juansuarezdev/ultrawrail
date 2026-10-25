#!/usr/bin/env swift
// Regenerates Resources/AppIcon.icns and the menu-bar template images from
// Resources/icon-source.png. Usage: swift scripts/make-icons.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")

func bitmap(_ pixels: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// App icon: the squircle of the source art, scaled to 824 px inside a 1024 canvas.
let source = NSImage(contentsOf: resources.appendingPathComponent("icon-source.png"))!
let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)!
// Squircle bounds in the source, inset a few px to drop the glow halo.
let crop = CGRect(x: 84, y: 72, width: 1086, height: 1086)
let art = cg.cropping(to: crop)!

func appIcon(pixels: Int) -> NSBitmapImageRep {
    bitmap(pixels) { c in
        let k = Double(pixels) / 1024
        let shape = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let path = CGPath(roundedRect: shape, cornerWidth: 0.2237 * 824 * k * 1.08,
                          cornerHeight: 0.2237 * 824 * k * 1.08, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k,
                    color: CGColor(gray: 0, alpha: 0.35))
        c.addPath(path)
        c.setFillColor(CGColor(red: 0.05, green: 0.08, blue: 0.3, alpha: 1))
        c.fillPath()
        c.restoreGState()
        c.addPath(path)
        c.clip()
        c.draw(art, in: shape)
    }
}

let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try write(appIcon(pixels: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try write(appIcon(pixels: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
try write(appIcon(pixels: 1024), to: resources.appendingPathComponent("AppIcon-1024.png"))

// Menu-bar glyph: black template image, three panes over a rail, 18 pt.
func glyph(scale: Int) -> NSBitmapImageRep {
    let s = Double(scale)
    return bitmap(18 * scale) { c in
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        let panes: [(x: Double, w: Double)] = [(-2, 5), (4, 7), (12, 6.5)]
        for pane in panes {
            let r = CGRect(x: pane.x * s, y: 6 * s, width: pane.w * s, height: 10 * s)
            c.addPath(CGPath(roundedRect: r, cornerWidth: 1.4 * s, cornerHeight: 1.4 * s, transform: nil))
            c.fillPath()
        }
        let rail = CGRect(x: 0, y: 2 * s, width: 18 * s, height: 2 * s)
        c.addPath(CGPath(roundedRect: rail, cornerWidth: s, cornerHeight: s, transform: nil))
        c.fillPath()
    }
}
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
    try write(glyph(scale: scale), to: resources.appendingPathComponent("MenuBarIconTemplate\(suffix).png"))
}
print("Icons written to Resources/")
