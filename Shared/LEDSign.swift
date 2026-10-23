import SwiftUI

/// Text on a black LED dot-matrix board. Latin letters, digits and common
/// punctuation use a real 5×7 pixel font; anything else (Chinese, emoji) is
/// drawn with the system font and shown through the same LED dot grid.
/// Picks the line breaks that make the dots as big as possible.
struct LEDSign: View {
    let text: String
    var color: Color = Color(red: 1, green: 0.62, blue: 0.12)
    /// Soft glow around lit dots (off in tinted StandBy night mode).
    var glow = true
    /// Show the dim unlit dots of the board.
    var showsUnlit = true
    var maxLines = 6

    var body: some View {
        let upper = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        GeometryReader { geo in
            if DotFont.canDraw(upper) {
                PixelFontBoard(text: upper.isEmpty ? " " : upper, size: geo.size, color: color,
                               glow: glow, showsUnlit: showsUnlit, maxLines: maxLines)
            } else {
                MaskedBoard(text: text, size: geo.size, color: color, glow: glow, showsUnlit: showsUnlit)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

// MARK: - 5×7 pixel font

private struct PixelFontBoard: View {
    let text: String
    let size: CGSize
    let color: Color
    let glow: Bool
    let showsUnlit: Bool
    let maxLines: Int

    var body: some View {
        let layout = DotLayout.best(for: text, in: size, maxLines: maxLines)
        Canvas { gc, canvas in
            let p = layout.pitch
            let py = layout.pitchY
            let r = min(p, py) * 0.4
            let gridW = CGFloat(layout.columns * 6 - 1) * p
            let gridH = CGFloat(layout.lines.count * 8 - 1) * py
            let ox = ((canvas.width - gridW) / 2).rounded()
            let oy = ((canvas.height - gridH) / 2).rounded()

            if showsUnlit {
                var unlit = Path()
                var y = oy.truncatingRemainder(dividingBy: py)
                while y < canvas.height {
                    var x = ox.truncatingRemainder(dividingBy: p)
                    while x < canvas.width {
                        unlit.addEllipse(in: CGRect(x: x + p / 2 - r, y: y + py / 2 - r, width: r * 2, height: r * 2))
                        x += p
                    }
                    y += py
                }
                gc.fill(unlit, with: .color(color.opacity(0.09)))
            }

            var lit = Path()
            for (row, line) in layout.lines.enumerated() {
                let chars = Array(line)
                let lead = (layout.columns - chars.count) * 6 / 2
                for (col, ch) in chars.enumerated() {
                    guard let rows = DotFont.glyphs[ch] else { continue }
                    for (gy, bits) in rows.enumerated() {
                        for gx in 0..<5 where bits & (1 << (4 - gx)) != 0 {
                            let dx = CGFloat(lead + col * 6 + gx)
                            let dy = CGFloat(row * 8 + gy)
                            lit.addEllipse(in: CGRect(x: ox + dx * p + p / 2 - r, y: oy + dy * py + py / 2 - r,
                                                      width: r * 2, height: r * 2))
                        }
                    }
                }
            }
            if glow {
                gc.drawLayer { layer in
                    layer.addFilter(.blur(radius: p * 0.9))
                    layer.fill(lit, with: .color(color.opacity(0.55)))
                }
            }
            gc.fill(lit, with: .color(color))
        }
    }
}

/// Where the line breaks go, and how big the dots can be.
struct DotLayout {
    var lines: [String]
    var columns: Int
    /// Horizontal dot spacing.
    var pitch: CGFloat
    /// Vertical dot spacing: up to 1.5× taller, so short words fill a tall sign.
    var pitchY: CGFloat = 0

    static let maxStretch: CGFloat = 1.5

    static func best(for text: String, in size: CGSize, maxLines: Int) -> DotLayout {
        let words = text.split(separator: " ").map(String.init)
        let total = text.count
        // Never break inside a word to gain dot size: lines are at least as
        // wide as the longest word.
        let longest = words.map(\.count).max() ?? 1
        var best = DotLayout(lines: [text], columns: max(1, total), pitch: 0)
        var bestArea: CGFloat = 0
        for limit in 1...max(1, maxLines) {
            // Narrowest line width (in characters) that fits in `limit` lines.
            var width = max(longest, Int((Double(total) / Double(limit)).rounded(.up)))
            var lines = wrap(words, width: width)
            while lines.count > limit, width < total {
                width += 1
                lines = wrap(words, width: width)
            }
            guard lines.count <= limit else { continue }
            let cols = lines.map(\.count).max() ?? 1
            let byWidth = size.width / CGFloat(cols * 6 - 1)
            let byHeight = size.height / CGFloat(lines.count * 8 - 1)
            let pitch = min(byWidth, byHeight)
            let pitchY = min(byHeight, pitch * maxStretch)
            // Bigger letters win: compare the area each dot gets.
            let area = pitch * pitchY
            if area > bestArea * 1.02 {
                best = DotLayout(lines: lines, columns: cols, pitch: pitch, pitchY: pitchY)
                bestArea = area
            }
        }
        return best
    }

    /// Greedy word wrap; words longer than a line are split.
    static func wrap(_ words: [String], width: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for var word in words {
            while word.count > width {
                if !line.isEmpty { lines.append(line); line = "" }
                lines.append(String(word.prefix(width)))
                word = String(word.dropFirst(width))
            }
            if line.isEmpty {
                line = word
            } else if line.count + 1 + word.count <= width {
                line += " " + word
            } else {
                lines.append(line)
                line = word
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.isEmpty ? [""] : lines
    }
}

/// A classic 5×7 LED font. Each glyph is 7 rows; bit 4 is the leftmost dot.
enum DotFont {
    static func canDraw(_ text: String) -> Bool {
        text.allSatisfy { glyphs[$0] != nil || $0 == "\n" }
    }

    static let glyphs: [Character: [UInt8]] = {
        func g(_ rows: String...) -> [UInt8] { rows.map { UInt8($0, radix: 2) ?? 0 } }
        return [
            " ": g("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
            "A": g("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
            "B": g("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
            "C": g("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
            "D": g("11100", "10010", "10001", "10001", "10001", "10010", "11100"),
            "E": g("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
            "F": g("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
            "G": g("01110", "10001", "10000", "10111", "10001", "10001", "01111"),
            "H": g("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
            "I": g("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
            "J": g("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
            "K": g("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
            "L": g("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
            "M": g("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
            "N": g("10001", "10001", "11001", "10101", "10011", "10001", "10001"),
            "O": g("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
            "P": g("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
            "Q": g("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
            "R": g("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
            "S": g("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
            "T": g("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
            "U": g("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
            "V": g("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
            "W": g("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
            "X": g("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
            "Y": g("10001", "10001", "10001", "01010", "00100", "00100", "00100"),
            "Z": g("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
            "0": g("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
            "1": g("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
            "2": g("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
            "3": g("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
            "4": g("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
            "5": g("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
            "6": g("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
            "7": g("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
            "8": g("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
            "9": g("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
            ".": g("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
            ",": g("00000", "00000", "00000", "00000", "01100", "00100", "01000"),
            "!": g("00100", "00100", "00100", "00100", "00100", "00000", "00100"),
            "?": g("01110", "10001", "00001", "00010", "00100", "00000", "00100"),
            "'": g("01100", "00100", "01000", "00000", "00000", "00000", "00000"),
            "’": g("01100", "00100", "01000", "00000", "00000", "00000", "00000"),
            "\"": g("01010", "01010", "01010", "00000", "00000", "00000", "00000"),
            "-": g("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
            "_": g("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
            ":": g("00000", "01100", "01100", "00000", "01100", "01100", "00000"),
            ";": g("00000", "01100", "01100", "00000", "01100", "00100", "01000"),
            "/": g("00000", "00001", "00010", "00100", "01000", "10000", "00000"),
            "&": g("01100", "10010", "10100", "01000", "10101", "10010", "01101"),
            "+": g("00000", "00100", "00100", "11111", "00100", "00100", "00000"),
            "=": g("00000", "00000", "11111", "00000", "11111", "00000", "00000"),
            "(": g("00010", "00100", "01000", "01000", "01000", "00100", "00010"),
            ")": g("01000", "00100", "00010", "00010", "00010", "00100", "01000"),
            "#": g("01010", "01010", "11111", "01010", "11111", "01010", "01010"),
            "@": g("01110", "10001", "00001", "01101", "10101", "10101", "01110"),
            "%": g("11000", "11001", "00010", "00100", "01000", "10011", "00011"),
            "$": g("00100", "01111", "10100", "01110", "00101", "11110", "00100"),
            "*": g("00000", "00100", "10101", "01110", "10101", "00100", "00000"),
            "<": g("00010", "00100", "01000", "10000", "01000", "00100", "00010"),
            ">": g("01000", "00100", "00010", "00001", "00010", "00100", "01000"),
        ]
    }()
}

// MARK: - Any script, through an LED mask

private struct MaskedBoard: View {
    let text: String
    let size: CGSize
    let color: Color
    let glow: Bool
    let showsUnlit: Bool

    var body: some View {
        // About 34 dots across the shorter side keeps CJK strokes readable.
        let pitch = max(2.5, min(size.width, size.height) / 34)
        ZStack {
            if showsUnlit {
                DotGrid(pitch: pitch).fill(color.opacity(0.09))
            }
            Text(text)
                .font(.system(size: size.height * 0.42, weight: .black, design: .rounded))
                .minimumScaleFactor(0.1)
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
                .padding(pitch)
                .frame(width: size.width, height: size.height)
                .mask(DotGrid(pitch: pitch, radiusRatio: 0.44).fill(.white))
                .shadow(color: glow ? color.opacity(0.7) : .clear, radius: glow ? pitch * 0.8 : 0)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A grid of round dots.
struct DotGrid: Shape {
    var pitch: CGFloat
    var radiusRatio: CGFloat = 0.4

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = pitch * radiusRatio
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                p.addEllipse(in: CGRect(x: x + pitch / 2 - r, y: y + pitch / 2 - r, width: r * 2, height: r * 2))
                x += pitch
            }
            y += pitch
        }
        return p
    }
}

#Preview("LED sign") {
    VStack(spacing: 12) {
        LEDSign(text: "DO NOT DISTURB", color: .red).frame(width: 170, height: 170)
        LEDSign(text: "PLEASE APPROVE THE REQUEST ON MY COMPUTER").frame(width: 364, height: 170)
        LEDSign(text: "请勿打扰", color: .pink).frame(width: 170, height: 170)
    }
    .padding()
    .background(.black)
}
