import Foundation

/// A 3×5 pixel font, the smallest that stays legible on an LED matrix.
///
/// Five rows leaves no room for descenders, so everything renders in capitals —
/// which is what real dot-matrix displays do for the same reason. Each glyph is
/// five rows of three bits, most significant bit leftmost.
enum MatrixFont {
    static let width = 3
    static let height = 5
    /// Blank column between characters.
    static let spacing = 1

    /// Anything unmapped renders blank rather than failing — a marquee is
    /// decoration, and an unknown character should cost a space, not a crash.
    static let blank: [UInt8] = [0, 0, 0, 0, 0]

    static func glyph(for character: Character) -> [UInt8] {
        glyphs[Character(character.uppercased())] ?? blank
    }

    /// Total columns a string occupies, including inter-character gaps.
    static func columns(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.count * (width + spacing) - spacing
    }

    /// Whether the pixel at (column, row) of `text` is lit. Rows count from the
    /// top; columns run the whole string, gaps included.
    static func isLit(text: String, column: Int, row: Int) -> Bool {
        guard row >= 0, row < height, column >= 0 else { return false }
        let stride = width + spacing
        let index = column / stride
        let inGlyph = column % stride
        guard inGlyph < width, index < text.count else { return false }

        let character = text[text.index(text.startIndex, offsetBy: index)]
        let bits = glyph(for: character)[row]
        return bits & (1 << (width - 1 - inGlyph)) != 0
    }

    private static let glyphs: [Character: [UInt8]] = [
        " ": [0b000, 0b000, 0b000, 0b000, 0b000],
        "A": [0b010, 0b101, 0b111, 0b101, 0b101],
        "B": [0b110, 0b101, 0b110, 0b101, 0b110],
        "C": [0b011, 0b100, 0b100, 0b100, 0b011],
        "D": [0b110, 0b101, 0b101, 0b101, 0b110],
        "E": [0b111, 0b100, 0b110, 0b100, 0b111],
        "F": [0b111, 0b100, 0b110, 0b100, 0b100],
        "G": [0b011, 0b100, 0b101, 0b101, 0b011],
        "H": [0b101, 0b101, 0b111, 0b101, 0b101],
        "I": [0b111, 0b010, 0b010, 0b010, 0b111],
        "J": [0b001, 0b001, 0b001, 0b101, 0b010],
        "K": [0b101, 0b101, 0b110, 0b101, 0b101],
        "L": [0b100, 0b100, 0b100, 0b100, 0b111],
        "M": [0b101, 0b111, 0b111, 0b101, 0b101],
        "N": [0b101, 0b111, 0b111, 0b111, 0b101],
        "O": [0b010, 0b101, 0b101, 0b101, 0b010],
        "P": [0b110, 0b101, 0b110, 0b100, 0b100],
        "Q": [0b010, 0b101, 0b101, 0b111, 0b011],
        "R": [0b110, 0b101, 0b110, 0b101, 0b101],
        "S": [0b011, 0b100, 0b010, 0b001, 0b110],
        "T": [0b111, 0b010, 0b010, 0b010, 0b010],
        "U": [0b101, 0b101, 0b101, 0b101, 0b111],
        "V": [0b101, 0b101, 0b101, 0b101, 0b010],
        "W": [0b101, 0b101, 0b111, 0b111, 0b101],
        "X": [0b101, 0b101, 0b010, 0b101, 0b101],
        "Y": [0b101, 0b101, 0b010, 0b010, 0b010],
        "Z": [0b111, 0b001, 0b010, 0b100, 0b111],
        "0": [0b111, 0b101, 0b101, 0b101, 0b111],
        "1": [0b010, 0b110, 0b010, 0b010, 0b111],
        "2": [0b110, 0b001, 0b010, 0b100, 0b111],
        "3": [0b110, 0b001, 0b010, 0b001, 0b110],
        "4": [0b101, 0b101, 0b111, 0b001, 0b001],
        "5": [0b111, 0b100, 0b110, 0b001, 0b110],
        "6": [0b011, 0b100, 0b111, 0b101, 0b111],
        "7": [0b111, 0b001, 0b010, 0b010, 0b010],
        "8": [0b111, 0b101, 0b111, 0b101, 0b111],
        "9": [0b111, 0b101, 0b111, 0b001, 0b110],
        ".": [0b000, 0b000, 0b000, 0b000, 0b010],
        "-": [0b000, 0b000, 0b111, 0b000, 0b000],
        "!": [0b010, 0b010, 0b010, 0b000, 0b010]
    ]
}
