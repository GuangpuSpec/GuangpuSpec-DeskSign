import AppIntents
import SwiftUI
import WidgetKit

@main
struct DeskSignWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DeskSignWidget()
    }
}

/// The desk sign as a widget: big LED letters on black. Made for StandBy,
/// which iPhone Duo shows when it stands in tent mode, and fine on the Home
/// Screen too.
struct DeskSignWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SignData.widgetKind,
                               intent: DeskSignWidgetConfiguration.self,
                               provider: SignProvider()) { entry in
            DeskSignWidgetView(entry: entry)
        }
        .configurationDisplayName("Desk Sign")
        .description("Your desk status in big LED letters. Add it to StandBy and it's on show whenever iPhone Duo stands in tent mode. Tap it to switch status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct SignEntry: TimelineEntry {
    let date: Date
    let text: String
    let style: SignStyle
    /// Follows the app's sign (so a tap can switch it), rather than one fixed status.
    let followsApp: Bool

    /// A sign is something you want on screen, so ask StandBy's Smart Stack
    /// to favour it.
    var relevance: TimelineEntryRelevance? { TimelineEntryRelevance(score: 100) }

    static let sample = SignEntry(date: .now, text: "DO NOT DISTURB", style: .neon, followsApp: true)
}

struct SignProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SignEntry { .sample }

    func snapshot(for configuration: DeskSignWidgetConfiguration, in context: Context) async -> SignEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: DeskSignWidgetConfiguration, in context: Context) async -> Timeline<SignEntry> {
        // The sign only changes when you change it; the app (or a tap on the
        // widget) asks WidgetKit to reload then, so no scheduled refreshes.
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: DeskSignWidgetConfiguration) -> SignEntry {
        let all = SignData.loadStatuses()
        if let pinned = configuration.status, let status = all.first(where: { $0.id == pinned.id }) {
            return SignEntry(date: .now, text: status.text, style: status.style, followsApp: false)
        }
        // Before the app has ever run there's nothing saved: show a preset.
        let status = SignData.current() ?? DeskStatus.presets[3]
        return SignEntry(date: .now, text: status.text, style: status.style, followsApp: true)
    }
}

struct DeskSignWidgetView: View {
    let entry: SignEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // In StandBy's night mode (and tinted Home Screens) the system recolours
        // the widget, so draw plain white dots without glow and let it tint them.
        let fullColor = renderingMode == .fullColor
        let sign = LEDSign(text: entry.text,
                           color: fullColor ? entry.style.ledColor : .white,
                           glow: fullColor,
                           showsUnlit: fullColor,
                           maxLines: family == .systemSmall ? 5 : 4)
            .padding(padding)

        Group {
            if entry.followsApp {
                Button(intent: NextSignStatusIntent()) { sign }
                    .buttonStyle(.plain)
            } else {
                sign
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }

    private var padding: CGFloat {
        switch family {
        case .systemSmall: 12
        case .systemMedium: 14
        default: 20
        }
    }
}

#Preview("Small", as: .systemSmall) {
    DeskSignWidget()
} timeline: {
    SignEntry.sample
    SignEntry(date: .now, text: "WORKING", style: .eInk, followsApp: true)
}

#Preview("Medium", as: .systemMedium) {
    DeskSignWidget()
} timeline: {
    SignEntry(date: .now, text: "PLEASE APPROVE THE REQUEST ON MY COMPUTER", style: .led, followsApp: true)
    SignEntry(date: .now, text: "去厕所了", style: .alarm, followsApp: true)
}
