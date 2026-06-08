#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("HelioBarApp/Resources")
let iconset = resources.appendingPathComponent("HelioBar.iconset")
let icns = resources.appendingPathComponent("HelioBar.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(pixelSize: Int, fileName: String) throws {
    let size = CGFloat(pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create icon bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = size * 0.055
    let backgroundRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let background = NSBezierPath(roundedRect: backgroundRect, xRadius: size * 0.19, yRadius: size * 0.19)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.20, alpha: 1)
    ])!
    gradient.draw(in: background, angle: 315)

    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    background.lineWidth = max(1, size * 0.012)
    background.stroke()

    let heartRect = NSRect(x: size * 0.235, y: size * 0.245, width: size * 0.53, height: size * 0.50)
    let minX = heartRect.minX
    let maxX = heartRect.maxX
    let minY = heartRect.minY
    let maxY = heartRect.maxY
    let midX = heartRect.midX
    let midY = heartRect.midY
    let w = heartRect.width
    let h = heartRect.height

    let heart = NSBezierPath()
    heart.move(to: CGPoint(x: midX, y: minY))
    heart.curve(to: CGPoint(x: minX, y: midY),
                controlPoint1: CGPoint(x: midX - w * 0.22, y: minY + h * 0.10),
                controlPoint2: CGPoint(x: minX, y: minY + h * 0.22))
    heart.curve(to: CGPoint(x: midX, y: maxY - h * 0.08),
                controlPoint1: CGPoint(x: minX, y: maxY - h * 0.08),
                controlPoint2: CGPoint(x: midX - w * 0.24, y: maxY))
    heart.curve(to: CGPoint(x: maxX, y: midY),
                controlPoint1: CGPoint(x: midX + w * 0.24, y: maxY),
                controlPoint2: CGPoint(x: maxX, y: maxY - h * 0.08))
    heart.curve(to: CGPoint(x: midX, y: minY),
                controlPoint1: CGPoint(x: maxX, y: minY + h * 0.22),
                controlPoint2: CGPoint(x: midX + w * 0.22, y: minY + h * 0.10))
    heart.close()

    NSColor(calibratedRed: 0.96, green: 0.20, blue: 0.29, alpha: 1).setFill()
    heart.fill()

    let pulse = NSBezierPath()
    pulse.move(to: CGPoint(x: size * 0.30, y: size * 0.50))
    pulse.line(to: CGPoint(x: size * 0.41, y: size * 0.50))
    pulse.line(to: CGPoint(x: size * 0.47, y: size * 0.62))
    pulse.line(to: CGPoint(x: size * 0.55, y: size * 0.39))
    pulse.line(to: CGPoint(x: size * 0.62, y: size * 0.50))
    pulse.line(to: CGPoint(x: size * 0.70, y: size * 0.50))
    pulse.lineWidth = max(2, size * 0.035)
    pulse.lineJoinStyle = .round
    pulse.lineCapStyle = .round
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
    pulse.stroke()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not render icon PNG")
    }

    try png.write(to: iconset.appendingPathComponent(fileName))
}

let variants: [(Int, String)] = [
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

for variant in variants {
    try drawIcon(pixelSize: variant.0, fileName: variant.1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

print("Generated \(icns.path)")
