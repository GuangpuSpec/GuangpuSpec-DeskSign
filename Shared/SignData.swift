import Foundation
import WidgetKit

/// The sign's statuses, kept in an App Group so the app and the StandBy
/// widget read and write the same data. Whoever changes it asks WidgetKit to
/// reload, so the widget always shows the latest status.
enum SignData {
    static let appGroup = "group.com.example.duovibes.desksign"
    static let widgetKind = "DeskSignWidget"

    static let statusesKey = "deskSign.statuses"
    static let currentKey = "deskSign.currentID"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Saved statuses; empty before the app first runs.
    static func loadStatuses() -> [DeskStatus] {
        guard let data = defaults.data(forKey: statusesKey),
              let saved = try? JSONDecoder().decode([DeskStatus].self, from: data) else { return [] }
        return saved
    }

    static func currentID() -> UUID? {
        defaults.string(forKey: currentKey).flatMap(UUID.init(uuidString:))
    }

    /// What the sign says right now.
    static func current() -> DeskStatus? {
        let all = loadStatuses()
        let id = currentID()
        return all.first { $0.id == id } ?? all.first
    }

    /// Switch to the next status (the widget's tap). Returns the new one.
    @discardableResult
    static func cycle() -> DeskStatus? {
        let all = loadStatuses()
        guard !all.isEmpty else { return nil }
        let index = all.firstIndex { $0.id == current()?.id } ?? 0
        let next = all[(index + 1) % all.count]
        defaults.set(next.id.uuidString, forKey: currentKey)
        reloadWidgets()
        return next
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// One-time copy of data saved by older versions (before the App Group).
    static func migrateFromStandardDefaults() {
        let group = defaults
        guard group.data(forKey: statusesKey) == nil,
              let old = UserDefaults.standard.data(forKey: statusesKey) else { return }
        group.set(old, forKey: statusesKey)
        group.set(UserDefaults.standard.string(forKey: currentKey), forKey: currentKey)
        group.set(UserDefaults.standard.integer(forKey: "deskSign.motionVersion"), forKey: "deskSign.motionVersion")
    }
}
