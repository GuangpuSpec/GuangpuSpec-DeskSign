import AppIntents
import WidgetKit

/// A status as the widget's settings see it. Reads the shared App Group, so
/// it works inside the widget extension without the app running.
struct SignStatusEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Status"
    static let defaultQuery = SignStatusQuery()

    let id: UUID
    let text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(text)")
    }

    init(_ status: DeskStatus) {
        id = status.id
        text = status.text
    }
}

struct SignStatusQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SignStatusEntity] {
        SignData.loadStatuses().filter { identifiers.contains($0.id) }.map(SignStatusEntity.init)
    }

    func suggestedEntities() async throws -> [SignStatusEntity] {
        SignData.loadStatuses().map(SignStatusEntity.init)
    }
}

/// The widget's settings (long-press the widget › Edit Widget).
struct DeskSignWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Desk Sign"
    static let description = IntentDescription("Leave Status empty to show whatever the app's sign shows.")

    /// Empty: follow the app. Set: this widget always shows that status.
    @Parameter(title: "Status")
    var status: SignStatusEntity?

    init() {}
}

/// Tap the widget: the sign switches to the next status, everywhere.
struct NextSignStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Desk Status"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        SignData.cycle()
        return .result()
    }
}
