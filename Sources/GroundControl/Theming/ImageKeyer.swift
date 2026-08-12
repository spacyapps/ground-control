// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import AppKit

/// Turns a themer's "background" into real transparency.
///
/// Image models cannot produce reliable alpha. They either paint the
/// checkerboard an editor would *show*, or drop transparency entirely — but
/// they will happily fill a flat colour, which is exactly why chroma keying
/// exists. Doing this at load means a generated file drops into a theme folder
/// and works, with no separate tool and nothing to regenerate.
enum ImageKeyer {
    enum Key: Equatable {
        /// Decide from the artwork: a vivid corner is a chroma key, a pale one
        /// is a drawn checkerboard.
        case auto
        case color(NSColor)
        case checkerboard

        /// Manifest values: "auto", "checkerboard", or any hex colour.
        init?(_ declared: String?) {
            guard let declared = declared?.trimmingCharacters(in: .whitespaces).lowercased(),
                  !declared.isEmpty else { return nil }
            switch declared {
            case "auto": self = .auto
            case "checkerboard", "checker": self = .checkerboard
            default:
                guard let color = NSColor(hex: declared) else { return nil }
                self = .color(color)
            }
        }
    }

    static func apply(_ key: Key, to image: CGImage) -> CGImage {
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
        ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        switch resolve(key, in: pixels, width: width) {
        case .checkerboard:
            floodFillFromEdges(&pixels, width: width, height: height)
        case .color(let color):
            chromaKey(&pixels, color: color)
        case .auto:
            break   // resolve() never returns .auto
        }
        return context.makeImage() ?? image
    }

    /// `auto` inspects the corner: artwork does not begin at the very edge, so
    /// whatever is there is the background the author meant to remove.
    private static func resolve(_ key: Key, in pixels: [UInt8], width: Int) -> Key {
        guard key == .auto else { return key }

        let index = (width + 1) * 4
        let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
        let saturation = max(red, max(green, blue)) - min(red, min(green, blue))

        // A vivid corner was painted deliberately; a colourless one is the
        // checkerboard pattern an editor draws for transparency.
        guard saturation > 100 else { return .checkerboard }
        return .color(NSColor(srgbRed: CGFloat(red) / 255,
                              green: CGFloat(green) / 255,
                              blue: CGFloat(blue) / 255,
                              alpha: 1))
    }

    // MARK: - Chroma key

    /// A soft key: a hard cutoff leaves the encoder's jagged staircase, so
    /// alpha ramps across a band and the blended edge pixels have the key's
    /// contribution subtracted back out.
    private static func chromaKey(_ pixels: inout [UInt8], color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        let key = (Int(srgb.redComponent * 255), Int(srgb.greenComponent * 255), Int(srgb.blueComponent * 255))
        let inner = 60.0, outer = 130.0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            let distance = Double((red - key.0) * (red - key.0)
                + (green - key.1) * (green - key.1)
                + (blue - key.2) * (blue - key.2)).squareRoot()

            if distance <= inner {
                pixels[index] = 0; pixels[index + 1] = 0
                pixels[index + 2] = 0; pixels[index + 3] = 0
                continue
            }
            guard distance < outer else { continue }

            let alpha = (distance - inner) / (outer - inner)
            func despill(_ value: Int, _ keyed: Int) -> UInt8 {
                let corrected = (Double(value) - Double(keyed) * (1 - alpha)) / max(alpha, 0.15)
                return UInt8(min(255, max(0, corrected)))
            }
            pixels[index] = despill(red, key.0)
            pixels[index + 1] = despill(green, key.1)
            pixels[index + 2] = despill(blue, key.2)
            pixels[index + 3] = UInt8(alpha * 255)
        }
    }

    // MARK: - Checkerboard

    /// Fills inward from every edge pixel.
    ///
    /// A drawn checkerboard is anti-aliased and carries many tones, so matching
    /// colours catches only part of it. But it is always at the *border* — real
    /// art does not begin at the frame edge — so flooding from the edges takes
    /// all of it and can never reach light greys inside the picture.
    private static func floodFillFromEdges(_ pixels: inout [UInt8], width: Int, height: Int) {
        func isBackdrop(_ cell: Int) -> Bool {
            let index = cell * 4
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            let brightest = max(red, max(green, blue)), darkest = min(red, min(green, blue))
            return darkest > 150 && brightest - darkest < 26
        }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        for x in 0..<width {
            stack.append(x)
            stack.append((height - 1) * width + x)
        }
        for y in 0..<height {
            stack.append(y * width)
            stack.append(y * width + width - 1)
        }

        while let cell = stack.popLast() {
            if visited[cell] { continue }
            visited[cell] = true
            guard isBackdrop(cell) else { continue }

            let index = cell * 4
            pixels[index] = 0; pixels[index + 1] = 0
            pixels[index + 2] = 0; pixels[index + 3] = 0

            let x = cell % width, y = cell / width
            if x > 0 { stack.append(cell - 1) }
            if x < width - 1 { stack.append(cell + 1) }
            if y > 0 { stack.append(cell - width) }
            if y < height - 1 { stack.append(cell + width) }
        }
    }
}
