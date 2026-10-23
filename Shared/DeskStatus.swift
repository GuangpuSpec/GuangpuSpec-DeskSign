import Foundation
import SwiftUI

struct DeskStatus: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var style: SignStyle
    var animation: SignAnimation
}

enum SignStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case neon, eInk, led, corporate, alarm

    var id: Self { self }

    var label: String {
        switch self {
        case .neon: String(localized: "Neon")
        case .eInk: String(localized: "E-ink")
        case .led: String(localized: "LED board")
        case .corporate: String(localized: "Corporate")
        case .alarm: String(localized: "Alarm")
        }
    }
}

/// How a sign moves. Raw values are saved, so never rename existing ones.
enum SignAnimation: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, shine, typewriter, pulse, flicker, shake, bounce, blink, marquee

    var id: Self { self }

    var label: String {
        switch self {
        case .none: String(localized: "Still")
        case .shine: String(localized: "Shine")
        case .typewriter: String(localized: "Typewriter")
        case .pulse: String(localized: "Pulse")
        case .flicker: String(localized: "Flicker")
        case .shake: String(localized: "Shake")
        case .bounce: String(localized: "Bounce")
        case .blink: String(localized: "Blink")
        case .marquee: String(localized: "Scroll")
        }
    }
}

extension DeskStatus {
    /// Built-in statuses, in the phone's language. Saved on first launch;
    /// "Restore Presets" rebuilds them in the current language.
    static var presets: [DeskStatus] {
        [
            // Each preset gets its own motion.
            DeskStatus(text: String(localized: "WORKING"), style: .eInk, animation: .typewriter),
            DeskStatus(text: String(localized: "OPEN FOR BUSINESS"), style: .corporate, animation: .shine),
            DeskStatus(text: String(localized: "IN THE BATHROOM"), style: .alarm, animation: .shake),
            DeskStatus(text: String(localized: "DO NOT DISTURB"), style: .neon, animation: .pulse),
            DeskStatus(text: String(localized: "PLEASE APPROVE THE REQUEST ON MY COMPUTER"), style: .led, animation: .marquee),
            DeskStatus(text: String(localized: "PRETENDING TO WORK"), style: .neon, animation: .flicker),
        ]
    }
}

extension SignStyle {
    /// The LED colour this style uses on the dot-matrix StandBy widget.
    var ledColor: Color {
        switch self {
        case .neon: Color(red: 1.0, green: 0.27, blue: 0.62)
        case .eInk: Color(red: 0.92, green: 0.94, blue: 0.96)
        case .led: Color(red: 1.0, green: 0.773, blue: 0.165)
        case .corporate: Color(red: 0.32, green: 0.78, blue: 1.0)
        case .alarm: Color(red: 1.0, green: 0.2, blue: 0.16)
        }
    }
}
