// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation
import MatrixKit

// A terminal preview for a `matrix.shape` formula. It parses with the real
// PatternFormula and steps a real phase clock, so what it draws is what the
// analyser draws — the feel knobs (jitter, speed) are approximated here rather
// than pulled from MatrixFeel, which lives in the app target.
//
//   swift run matrix-preview "<formula>"
//   swift run matrix-preview "wave(pos)" --speed fast --jitter chaotic
//   swift run matrix-preview "pyramid(pos) * decay(0.6)" --state done
//   swift run matrix-preview "<formula>" --frames 30    # non-interactive
//
// Ctrl-C to quit the live view.

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
guard let formulaSource = args.first, !formulaSource.hasPrefix("-") else {
    FileHandle.standardError.write(Data("""
    usage: matrix-preview "<formula>" [options]
      --speed  slow|medium|fast      how fast phase advances (default medium)
      --jitter none|calm|lively|chaotic   per-bar noise (default none)
      --energy 0..1                  amplitude the shape is scaled by (default 0.85)
      --state  working|needsInput|done   default working
      --bars   N                     columns (default 48)
      --rows   N                     LED rows (default 5)
      --decay  S                     seconds since a finish, for decay() (default 0)
      --frames N                     print N frames and exit (no live loop)
    \n
    """.utf8))
    exit(2)
}
args.removeFirst()

func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: "--\(name)"), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let speed = option("speed") ?? "medium"
let jitterName = option("jitter") ?? "none"
let energy = Double(option("energy") ?? "") ?? 0.85
let state = option("state") ?? "working"
let bars = Int(option("bars") ?? "") ?? 48
let rows = Int(option("rows") ?? "") ?? 5
let decayElapsed = Double(option("decay") ?? "") ?? 0
let frames = Int(option("frames") ?? "") ?? 0

// Mirrors MatrixFeel — kept small on purpose.
let phaseStep: Double = ["slow": 0.05, "medium": 0.09, "fast": 0.16][speed] ?? 0.09
let jitter: ClosedRange<Double> = [
    "none": 1.0...1.0, "calm": 0.90...1.0, "lively": 0.75...1.0, "chaotic": 0.45...1.0
][jitterName] ?? 1.0...1.0

// MARK: - Parse

guard let formula = PatternFormula.parse(
    formulaSource, allowsDecay: state == "done"
) else {
    FileHandle.standardError.write(Data("formula did not parse — see Console for the reason\n".utf8))
    exit(1)
}

// MARK: - Render

let glyphs = " ▁▂▃▄▅▆▇█"   // fine height when rows == 1, else a per-row grid

func render(phase: Double) -> String {
    let sampler = formula.sampler(
        phase: CGFloat(phase), energy: CGFloat(energy), count: bars, decayElapsed: decayElapsed
    )
    var grid = Array(repeating: Array(repeating: " ", count: bars), count: rows)
    for column in 0..<bars {
        let pos = bars == 1 ? 0.5 : Double(column) / Double(bars - 1)
        let raw = Double(sampler.height(pos: pos, bar: column))
        let wobble = Double.random(in: jitter)
        let height = max(0, min(1, energy * wobble * raw))
        let lit = Int((height * Double(rows)).rounded())
        for row in 0..<rows where row < lit {
            grid[rows - 1 - row][column] = "█"
        }
    }
    return grid.map { $0.joined() }.joined(separator: "\n")
}

if frames > 0 {
    var phase = 0.0
    for _ in 0..<frames {
        print(render(phase: phase))
        print(String(repeating: "─", count: bars))
        phase += phaseStep
    }
    exit(0)
}

// Live loop.
print("\u{1B}[?25l", terminator: "")                    // hide cursor
defer { print("\u{1B}[?25h", terminator: "") }          // restore on exit
signal(SIGINT) { _ in print("\u{1B}[?25h"); exit(0) }

var phase = 0.0
while true {
    print("\u{1B}[H\u{1B}[2J", terminator: "")          // home + clear
    print("  \(formulaSource)")
    print("  speed=\(speed)  jitter=\(jitterName)  energy=\(energy)  state=\(state)\n")
    print(render(phase: phase))
    fflush(stdout)
    phase += phaseStep
    Thread.sleep(forTimeInterval: 1.0 / 24.0)
}
