import SwiftUI

/// Renders one status as a sign. Used full screen in tent mode and as small
/// previews in the list and editor.
struct SignView: View {
    let status: DeskStatus
    /// Full-size sign: shifts a few points every minute to spare the OLED.
    var isLive = false

    var body: some View {
        if status.animation == .none {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                frame(at: context.date)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                frame(at: context.date)
            }
        }
    }

    private func frame(at date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let look = SignLook(style: status.style)
        return GeometryReader { geo in
            ZStack {
                look.background
                if status.style == .led { LEDGrid() }
                content(look: look, size: geo.size, time: t)
                    .offset(isLive ? burnInShift(t) : .zero)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func content(look: SignLook, size: CGSize, time t: TimeInterval) -> some View {
        let fontSize = max(10, min(size.height * 0.42, size.width * 0.22))

        switch status.animation {
        case .marquee:
            Marquee(
                label: styled(Text(status.text), look: look, fontSize: fontSize)
                    .lineLimit(1)
                    .fixedSize(),
                time: t,
                width: size.width
            )
            .frame(maxHeight: .infinity)

        case .typewriter:
            fitted(styled(Text(Motion.typewriter(status.text, time: t)), look: look, fontSize: fontSize),
                   size: size)

        case .shine:
            let label = fitted(styled(Text(status.text), look: look, fontSize: fontSize), size: size)
            label.overlay {
                Motion.shineBand(time: t, width: size.width)
                    .mask(label)
            }

        case .none, .pulse, .flicker, .shake, .bounce, .blink:
            let m = Motion.transform(status.animation, time: t, size: size)
            fitted(styled(Text(status.text), look: look, fontSize: fontSize), size: size)
                .opacity(m.opacity)
                .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                .rotationEffect(.degrees(m.rotation))
                .offset(m.offset)
        }
    }

    private func styled(_ text: Text, look: SignLook, fontSize: CGFloat) -> some View {
        text
            .font(look.font(size: fontSize))
            .foregroundStyle(look.foreground)
            .shadow(color: look.glow, radius: look.glow == .clear ? 0 : fontSize * 0.12)
            .shadow(color: look.glow, radius: look.glow == .clear ? 0 : fontSize * 0.3)
    }

    private func fitted(_ label: some View, size: CGSize) -> some View {
        label
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.1)
            .padding(size.width * 0.06)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Small circular drift, one step per minute.
    private func burnInShift(_ t: TimeInterval) -> CGSize {
        let minute = (t / 60).rounded(.down)
        let angle = minute * .pi / 4
        return CGSize(width: cos(angle) * 4, height: sin(angle) * 4)
    }
}

/// One frame's worth of movement for the simple motions.
struct MotionFrame {
    var opacity = 1.0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation = 0.0
    var offset = CGSize.zero
}

/// All motions are pure functions of time, so every sign stays in step with
/// the TimelineView and nothing needs state.
enum Motion {
    static func transform(_ animation: SignAnimation, time t: TimeInterval, size: CGSize) -> MotionFrame {
        var f = MotionFrame()
        switch animation {
        case .pulse:
            // Slow breathing: glow and swell together.
            let s = 0.5 + 0.5 * sin(t * 2.4)
            f.opacity = 0.6 + 0.4 * s
            f.scaleX = 0.97 + 0.05 * s
            f.scaleY = f.scaleX

        case .blink:
            f.opacity = t.truncatingRemainder(dividingBy: 1.2) < 0.75 ? 1 : 0.08

        case .shake:
            // A sharp burst of shaking, then a pause. Urgent, like it's waiting.
            let c = t.truncatingRemainder(dividingBy: 1.8)
            if c < 0.6 {
                let decay = 1 - c / 0.6
                f.offset.width = sin(c * 70) * size.width * 0.02 * decay
                f.rotation = sin(c * 55) * 2.5 * decay
            }

        case .flicker:
            // A dodgy neon tube: steady, then a stutter now and then.
            let c = t.truncatingRemainder(dividingBy: 4.0)
            if c > 2.6 && c < 3.4 {
                let bucket = UInt64(max(0, t * 20))
                let h = (bucket &* 0x9E37_79B9_7F4A_7C15) >> 59   // 0...31
                f.opacity = h < 13 ? 0.12 : (h < 18 ? 0.55 : 1)
            }

        case .bounce:
            // Hops, with a little squash when it lands.
            let p = (t * 1.6).truncatingRemainder(dividingBy: 1)
            let height = abs(sin(p * .pi))
            f.offset.height = -height * size.height * 0.08
            let squash = max(0, 0.15 - height) / 0.15
            f.scaleX = 1 + 0.08 * squash
            f.scaleY = 1 - 0.08 * squash

        case .none, .shine, .typewriter, .marquee:
            break
        }
        return f
    }

    /// Text typed out one character at a time, held, then retyped. The untyped
    /// part is drawn invisibly so the layout never jumps.
    static func typewriter(_ text: String, time t: TimeInterval) -> AttributedString {
        let chars = Array(text)
        let n = chars.count
        guard n > 0 else { return AttributedString(text) }
        let speed = n > 20 ? 18.0 : 7.0         // characters per second
        let cycle = Double(n) / speed + 2.5     // type, then hold
        let c = t.truncatingRemainder(dividingBy: cycle)
        let k = min(n, Int(c * speed))

        var shown = AttributedString(String(chars[..<k]))
        var cursor = AttributedString("▍")
        if Int(t * 2.5) % 2 == 1 { cursor.foregroundColor = Color.clear }
        var rest = AttributedString(String(chars[k...]))
        rest.foregroundColor = Color.clear
        shown.append(cursor)
        shown.append(rest)
        return shown
    }

    /// A diagonal band of light that sweeps across, then waits.
    static func shineBand(time t: TimeInterval, width: CGFloat) -> some View {
        let period = 3.2
        let sweep = 1.3
        let p = min(t.truncatingRemainder(dividingBy: period) / sweep, 1.2)
        let x = -width * 0.8 + CGFloat(p) * width * 1.6
        return LinearGradient(
            colors: [.clear, .white.opacity(0.85), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: max(width * 0.25, 20))
        .rotationEffect(.degrees(18))
        .offset(x: x)
        .blendMode(.plusLighter)
    }
}

/// Horizontal scroll that wraps. Measures the text, then slides it.
private struct Marquee<Label: View>: View {
    let label: Label
    let time: TimeInterval
    let width: CGFloat
    @State private var textWidth: CGFloat = 0

    var body: some View {
        let gap = width * 0.3
        let cycle = max(textWidth + gap, 1)
        let speed = max(width * 0.35, 60) // points per second
        let x = -CGFloat((time * speed).truncatingRemainder(dividingBy: Double(cycle)))
        HStack(spacing: gap) {
            label
            label
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { total in
            textWidth = (total - gap) / 2
        }
        .offset(x: x)
        .frame(width: width, alignment: .leading)
    }
}

/// Faint dot-matrix lines for the LED style.
private struct LEDGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 6
            var path = Path()
            var y: CGFloat = 0
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1.5))
                y += step
            }
            var x: CGFloat = 0
            while x < size.width {
                path.addRect(CGRect(x: x, y: 0, width: 1.5, height: size.height))
                x += step
            }
            ctx.fill(path, with: .color(.black.opacity(0.55)))
        }
        .allowsHitTesting(false)
        .blendMode(.multiply)
        .zIndex(1)
    }
}

/// Colors and type for each style.
struct SignLook {
    let style: SignStyle

    var background: Color {
        switch style {
        case .neon: Color(red: 0.05, green: 0.02, blue: 0.08)
        case .eInk: Color(red: 0.93, green: 0.92, blue: 0.88)
        case .led: .black
        case .corporate: Color(red: 0.07, green: 0.14, blue: 0.30)
        case .alarm: Color(red: 0.80, green: 0.06, blue: 0.08)
        }
    }

    var foreground: Color {
        switch style {
        case .neon: Color(red: 1.0, green: 0.30, blue: 0.75)
        case .eInk: Color(red: 0.12, green: 0.12, blue: 0.12)
        case .led: Color(red: 1.0, green: 0.68, blue: 0.10)
        case .corporate: .white
        case .alarm: .white
        }
    }

    var glow: Color {
        switch style {
        case .neon: foreground.opacity(0.8)
        case .led: foreground.opacity(0.6)
        case .eInk, .corporate, .alarm: .clear
        }
    }

    func font(size: CGFloat) -> Font {
        switch style {
        case .neon: .system(size: size, weight: .heavy, design: .rounded)
        case .eInk: .system(size: size, weight: .regular, design: .serif)
        case .led: .system(size: size, weight: .bold, design: .monospaced)
        case .corporate: .system(size: size, weight: .semibold)
        case .alarm: .system(size: size, weight: .black).width(.condensed)
        }
    }
}

#Preview("All presets", traits: .landscapeLeft) {
    ScrollView {
        ForEach(DeskStatus.presets) { status in
            SignView(status: status)
                .frame(height: 160)
        }
    }
}
