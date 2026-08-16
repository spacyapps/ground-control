// SPDX-License-Identifier: AGPL-3.0-or-later
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

/// Walks in from the left and reports the column where the ornate corner ends
/// and the plain girder begins.
///
/// Measured by how deep the artwork hangs in each column, not by where its top
/// edge sits. The first version used the top edge — the profile settles once
/// the silhouette stops moving — and it read 10 on artwork whose corner towers
/// happen to have flat tops, which is a cap that would slice the whole corner
/// into the tiled strip. Depth cannot be fooled that way: the girder is a thin
/// band and every ornament is thicker than it.
struct Silhouette {
    let width: Int
    let height: Int
    private let opaque: [Bool]

    init?(_ image: CGImage, key: (Int, Int, Int) = (0, 255, 0)) {
        width = image.width
        height = image.height
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

        var mask = [Bool](repeating: false, count: width * height)
        for cell in 0..<(width * height) {
            let index = cell * 4
            guard pixels[index + 3] > 120 else { continue }
            let red = Int(pixels[index]) - key.0
            let green = Int(pixels[index + 1]) - key.1
            let blue = Int(pixels[index + 2]) - key.2
            mask[cell] = red * red + green * green + blue * blue > 130 * 130
        }
        opaque = mask
    }

    /// Row 0 is the top of the picture, which is how the caps are described.
    func isArtwork(_ x: Int, _ y: Int) -> Bool {
        opaque[(height - 1 - y) * width + x]
    }

    /// How far the left girder's inner face sits from the edge, on this row.
    func leftInnerFace(atRow y: Int) -> Int {
        var inner = -1
        for x in 0..<(width / 2) where isArtwork(x, y) { inner = x }
        return inner
    }

    /// The same for the top girder, down this column.
    func topInnerFace(atColumn x: Int) -> Int {
        var inner = -1
        for y in 0..<(height / 2) where isArtwork(x, y) { inner = y }
        return inner
    }
}

func girderStart(of art: Silhouette) -> Int? {
    let width = art.width, height = art.height
    func isArtwork(_ x: Int, _ y: Int) -> Bool { art.isArtwork(x, y) }

    // How far down the artwork reaches in each column, across the top half.
    var depth = [Int](repeating: 0, count: width)
    for x in 0..<width {
        for y in 0..<(height / 2) where isArtwork(x, y) { depth[x] = y }
    }

    // The girder is whatever the middle of the edge measures.
    let middle = width / 2
    let girder = depth[(middle - 10)...(middle + 10)].min() ?? 0
    guard girder > 0 else { return nil }

    // The cap goes past the last column that is deeper than the girder, with a
    // little tolerance for the odd protruding rivet.
    let limit = width / 2
    guard let last = (0..<limit).last(where: { depth[$0] > girder + 8 }) else { return nil }
    return last + 1
}

/// The cap that makes a tiled frame join cleanly.
///
/// `tile` repeats the band between the caps, so that band's two ends meet at
/// every repeat. Where a girder bows even slightly — hand-drawn and generated
/// art both do — the join shows as a step, and the cap is what decides which
/// two rows have to match. The smallest cap that clears the ornament is not
/// automatically the one that joins best.
///
/// Sweeps outward from `floor` and reports the first cap whose seam is within a
/// pixel of the best on offer, because a smaller cap keeps the frame lighter and
/// the panel's minimum size lower.
func seamAt(_ cap: Int, of art: Silhouette) -> Int {
    let vertical = abs(art.leftInnerFace(atRow: cap)
        - art.leftInnerFace(atRow: art.height - 1 - cap))
    let horizontal = abs(art.topInnerFace(atColumn: cap)
        - art.topInnerFace(atColumn: art.width - 1 - cap))
    return max(vertical, horizontal)
}

func seamlessCap(of art: Silhouette, from floor: Int) -> (cap: Int, seam: Int)? {
    let reach = min(art.width, art.height) / 2
    guard floor < reach else { return nil }

    let candidates = (floor..<min(floor + 60, reach)).map { ($0, seamAt($0, of: art)) }
    guard let best = candidates.map(\.1).min() else { return nil }
    return candidates.first { $0.1 <= best + 1 }
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

guard let art = Silhouette(frames[0]) else { exit(0) }

guard let floor = girderStart(of: art) else {
    print("could not find a flat girder — this art may not suit nine-slice at all")
    exit(0)
}
print("ornament ends at: \(floor)px  (caps are points, drawn 1:1)")

// `tile` repeats the band between the caps, so a bowed girder shows a step
// wherever it wraps. Worth reporting even when the answer is "no improvement".
let floorSeam = seamAt(floor, of: art)
if let (cap, seam) = seamlessCap(of: art, from: floor), cap != floor, seam < floorSeam {
    print("suggested capInsets: \(cap)   — tiled seam \(seam)px here, \(floorSeam)px at \(floor)")
    print("minimum panel size: \(cap * 2)pt")
} else {
    print("suggested capInsets: \(floor)   — tiled seam \(floorSeam)px, nothing larger improves it")
    print("minimum panel size: \(floor * 2)pt")
}
