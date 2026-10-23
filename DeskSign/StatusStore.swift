import Foundation
import Observation
import WidgetKit

/// Statuses plus which one is on the sign. Shared so App Intents can change
/// the sign while it's standing in tent mode. Saved in the App Group, so the
/// StandBy widget shows the same thing; every change reloads the widget.
@MainActor
@Observable
final class StatusStore {
    static let shared = StatusStore()

    private(set) var statuses: [DeskStatus]
    private(set) var currentID: DeskStatus.ID?

    var current: DeskStatus? {
        statuses.first { $0.id == currentID } ?? statuses.first
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let statusesKey = SignData.statusesKey
    private static let currentKey = SignData.currentKey

    init(defaults: UserDefaults = SignData.defaults) {
        SignData.migrateFromStandardDefaults()
        self.defaults = defaults
        var firstRun = false
        if let data = defaults.data(forKey: Self.statusesKey),
           let saved = try? JSONDecoder().decode([DeskStatus].self, from: data),
           !saved.isEmpty {
            statuses = saved
        } else {
            statuses = DeskStatus.presets
            firstRun = true
        }
        currentID = defaults.string(forKey: Self.currentKey).flatMap(UUID.init(uuidString:))
        // Presets get fresh UUIDs on every launch; pin them on first run so a
        // saved selection keeps pointing at something.
        if firstRun {
            save()
        } else {
            renameRetiredPresets()
            translateUntouchedPresets()
            upgradePresetMotions()
        }
        defaults.set(Self.currentMotionVersion, forKey: Self.motionVersionKey)
    }

    private static let motionVersionKey = "deskSign.motionVersion"
    /// Bump when the presets' default motions change.
    private static let currentMotionVersion = 2

    /// Once per motion version: untouched presets (text still the preset's,
    /// in English or the phone's language) take the presets' new motions.
    private func upgradePresetMotions() {
        guard defaults.integer(forKey: Self.motionVersionKey) < Self.currentMotionVersion else { return }
        let presets = DeskStatus.presets
        guard presets.count == Self.englishPresetTexts.count else { return }
        var changed = false
        for i in statuses.indices {
            let text = statuses[i].text
            let k = Self.englishPresetTexts.firstIndex(of: text)
                ?? presets.firstIndex { $0.text == text }
            if let k, statuses[i].animation != presets[k].animation {
                statuses[i].animation = presets[k].animation
                changed = true
            }
        }
        if changed { save() }
    }

    /// The presets as first shipped, in English. A saved status whose text is
    /// still exactly one of these gets the phone's-language version, so
    /// switching the phone to Chinese also switches the untouched presets.
    private static let englishPresetTexts = [
        "WORKING",
        "OPEN FOR BUSINESS",
        "IN THE BATHROOM",
        "DO NOT DISTURB",
        "PLEASE APPROVE THE REQUEST ON MY COMPUTER",
        "PRETENDING TO WORK",
    ]

    /// Older preset wordings (English and Chinese) and the preset that replaced each.
    private static let retiredPresetTexts: [String: Int] = [
        "CURRENTLY WORKING": 0,
        "正在工作": 0,
        "IF MY COMPUTER ASKS FOR APPROVAL, PLEASE CLICK APPROVE FOR ME. THANKS!": 4,
        "如果我的电脑弹出授权请求，请帮我点「允许」，谢谢！": 4,
    ]

    /// Untouched presets from older versions take the new wording.
    private func renameRetiredPresets() {
        let presets = DeskStatus.presets
        var changed = false
        for i in statuses.indices {
            if let k = Self.retiredPresetTexts[statuses[i].text], k < presets.count {
                statuses[i].text = presets[k].text
                changed = true
            }
        }
        if changed { save() }
    }

    /// Re-read what's saved: the widget may have switched the status while
    /// the app was in the background.
    func reloadFromDisk() {
        if let data = defaults.data(forKey: Self.statusesKey),
           let saved = try? JSONDecoder().decode([DeskStatus].self, from: data), !saved.isEmpty,
           saved != statuses {
            statuses = saved
        }
        let id = defaults.string(forKey: Self.currentKey).flatMap(UUID.init(uuidString:))
        if id != currentID { currentID = id }
    }

    private func translateUntouchedPresets() {
        let localized = DeskStatus.presets.map(\.text)
        guard localized.count == Self.englishPresetTexts.count else { return }
        var changed = false
        for i in statuses.indices {
            if let k = Self.englishPresetTexts.firstIndex(of: statuses[i].text),
               statuses[i].text != localized[k] {
                statuses[i].text = localized[k]
                changed = true
            }
        }
        if changed { save() }
    }

    func select(_ id: DeskStatus.ID) {
        guard statuses.contains(where: { $0.id == id }) else { return }
        currentID = id
        save()
    }

    /// Next (or previous) status, wrapping around. Used by double-tap and Siri.
    func cycle(forward: Bool = true) {
        guard !statuses.isEmpty else { return }
        let index = statuses.firstIndex { $0.id == current?.id } ?? 0
        let step = forward ? 1 : -1
        let next = (index + step + statuses.count) % statuses.count
        select(statuses[next].id)
    }

    func upsert(_ status: DeskStatus) {
        if let i = statuses.firstIndex(where: { $0.id == status.id }) {
            statuses[i] = status
        } else {
            statuses.append(status)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        // Keep at least one status so the sign is never blank.
        guard statuses.count - offsets.count >= 1 else { return }
        for i in offsets.sorted(by: >) { statuses.remove(at: i) }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        // Manual move so this file doesn't need SwiftUI.
        let moving = source.sorted().map { statuses[$0] }
        var remaining = statuses
        for i in source.sorted(by: >) { remaining.remove(at: i) }
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertAt)
        statuses = remaining
        save()
    }

    func restorePresets() {
        statuses = DeskStatus.presets
        currentID = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(statuses) {
            defaults.set(data, forKey: Self.statusesKey)
        }
        defaults.set(currentID?.uuidString, forKey: Self.currentKey)
        WidgetCenter.shared.reloadTimelines(ofKind: SignData.widgetKind)
    }
}
