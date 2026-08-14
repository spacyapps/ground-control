// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak
//
// Resizes frame artwork — animated or still — to the size a nine-slice theme
// can actually use, and measures where its cap insets belong.
//
//   swift Scripts/fit-frame-art.swift <in.gif> <out.gif> [width]
//
// Nine-slice caps are drawn **1:1 in points**, so the artwork's pixel size is
// not a quality setting — it sets how thick the frame appears on screen and how
// narrow the panel may get. Art at twice the intended size does not render
// twice as sharp; it renders twice as heavy, and the caps measured for the
// smaller version now cut through the corner instead of past it.
//
// That is the failure this exists to prevent: a 900px redraw of art whose
// manifest still said `capInsets: 75` put the corner tower into the *tiled*
// edge strip, which then repeated it down the sides.
//
// The background colour is left alone. Frame art is keyed at load, and keying
// before the resample would mean resampling 1-bit GIF alpha into hard jagged
// edges; leaving the flat colour in place lets the resample blend it like any
// other pixel, which is what the keyer's soft band expects.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: fit-frame-art <in> <out> [width]\n".utf8))
    exit(2)
}

let inputPath = arguments[1]
let outputPath = arguments[2]
let target = arguments.count > 3 ? (Int(arguments[3]) ?? 450) : 450

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil) else {
    fail("cannot read \(inputPath)")
}
let count = CGImageSourceGetCount(source)
guard count > 0 else { fail("no frames in \(inputPath)") }

/// The file's own timing, kept so a resized animation still runs at the speed
/// its author saw. Read the same way the app reads it.
func delay(at index: Int) -> Double {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    else { return 0.1 }
    let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
    let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        ?? png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double
    let clamped = gif?[kCGImagePropertyGIFDelayTime] as? Double
        ?? png?[kCGImagePropertyAPNGDelayTime] as? Double
    let value = unclamped ?? clamped ?? 0
    return value < 0.02 ? 0.1 : value
}

func resample(_ image: CGImage, to side: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()
}

// MARK: - Where the caps belong

/// Walks in from the left along the top of the artwork and reports the column
/// where the silhouette stops moving.
///
/// The ornate corner — towers, dishes, solar arrays — has a wildly varying
/// profile; the girder that follows it is flat. That transition is the only
/// correct place to cut a cap, and it is measurable rather than a matter of
/// taste, so nobody has to guess at it again.
func girderStart(of image: CGImage, key: (Int, Int, Int) = (0, 255, 0)) -> Int? {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func isArtwork(_ x: Int, _ y: Int) -> Bool {
        let index = ((height - 1 - y) * width + x) * 4
        guard pixels[index + 3] > 60 else { return false }
        let red = Int(pixels[index]) - key.0
        let green = Int(pixels[index + 1]) - key.1
        let blue = Int(pixels[index + 2]) - key.2
        return red * red + green * green + blue * blue > 130 * 130
    }

    var top = [Int](repeating: height, count: width)
    for x in 0..<width {
        for y in 0..<height where isArtwork(x, y) {
            top[x] = y
            break
        }
    }

    let run = 40
    for x in 0..<max(0, width - run) {
        let window = top[x..<(x + run)]
        guard let low = window.min(), let high = window.max(), low < height else { continue }
        if high - low <= 3 { return x }
    }
    return nil
}

// MARK: - Run

guard let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot decode frame 0") }
let side = min(first.width, first.height)
guard first.width == first.height else {
    fail("expected square artwork, got \(first.width)x\(first.height)")
}

var frames: [CGImage] = []
var delays: [Double] = []
for index in 0..<count {
    guard let raw = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
    guard let scaled = resample(raw, to: target) else { continue }
    frames.append(scaled)
    delays.append(delay(at: index))
}
guard !frames.isEmpty else { fail("nothing decoded") }

let type: UTType = frames.count > 1 ? .gif : .png
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL,
    type.identifier as CFString,
    frames.count,
    nil
) else { fail("cannot write \(outputPath)") }

if frames.count > 1 {
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
}
for (index, frame) in frames.enumerated() {
    let properties: CFDictionary? = frames.count > 1
        ? [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delays[index],
            kCGImagePropertyGIFUnclampedDelayTime: delays[index]
        ]] as CFDictionary
        : nil
    CGImageDestinationAddImage(destination, frame, properties)
}
guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(outputPath)") }

let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath)
let bytes = (attributes?[.size] as? Int) ?? 0
print("wrote \(outputPath) — \(frames.count) frame(s), \(side)px -> \(target)px, \(bytes / 1024)KB")

if let cap = girderStart(of: frames[0]) {
    print("measured cap inset: \(cap)  (the girder starts there; caps are points, drawn 1:1)")
    print("minimum sensible panel width: \(cap * 2)pt")
} else {
    print("could not find a flat girder — this art may not suit nine-slice at all")
}
