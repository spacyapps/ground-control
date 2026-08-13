// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak
//
// Renders square artwork into a macOS app icon: Apple's margin, rounded
// corners, transparent surround.
//
//   swift Scripts/make-app-icon.swift <source.png> <out.png> [canvas]
//
// Recent macOS does not round an icon for you — whatever the .icns contains is
// what the Dock shows, hard corners and all. So the shape has to be baked in,
// and the artwork inset to the same proportions Apple's own icons use, or this
// one sits noticeably larger than its neighbours.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-app-icon <source> <out> [canvas]\n".utf8))
    exit(2)
}

let sourcePath = arguments[1]
let outputPath = arguments[2]
let canvas = arguments.count > 3 ? (Double(arguments[3]) ?? 1024) : 1024

// Apple's macOS icon grid: the rounded square covers about 80% of the canvas,
// with a corner radius near 22% of that square. Measured off the system icons
// rather than guessed — an icon that fills its canvas looks oversized in the
// Dock beside every other app.
let inset = canvas * 0.10
let side = canvas - inset * 2
let radius = side * 0.225

guard let source = NSImage(contentsOfFile: sourcePath) else {
    FileHandle.standardError.write(Data("cannot read \(sourcePath)\n".utf8))
    exit(1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("cannot allocate canvas\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let square = NSRect(x: inset, y: inset, width: side, height: side)
let shape = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)
shape.addClip()

// Scaled to *cover* the rounded square: source art is square already, but a
// letterboxed icon with transparent bands inside its own corners would look
// like a mistake.
let size = source.size
let scale = max(side / size.width, side / size.height)
let drawn = NSSize(width: size.width * scale, height: size.height * scale)
source.draw(
    in: NSRect(
        x: square.midX - drawn.width / 2,
        y: square.midY - drawn.height / 2,
        width: drawn.width,
        height: drawn.height
    ),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("cannot encode png\n".utf8))
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath) — \(Int(canvas))px canvas, \(Int(side))px icon, \(Int(radius))px radius")
} catch {
    FileHandle.standardError.write(Data("cannot write \(outputPath): \(error)\n".utf8))
    exit(1)
}
