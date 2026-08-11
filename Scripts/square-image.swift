// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Walter Mak
//
// Centres an image on a transparent square canvas. Run via `swift`.
// Icon sources are rarely square, and sips would squash rather than pad —
// a distorted icon is the most visible flaw a menu-bar app can have.
import AppKit

guard CommandLine.arguments.count >= 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else { exit(1) }
let destination = URL(fileURLWithPath: CommandLine.arguments[2])

let size = image.size
let side = max(size.width, size.height) * 1.18   // breathing room inside the square
let canvas = NSImage(size: NSSize(width: side, height: side))

canvas.lockFocus()
image.draw(
    in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
               width: size.width, height: size.height),
    from: .zero, operation: .sourceOver, fraction: 1
)
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: destination)
print("squared to \(Int(side))x\(Int(side))")
