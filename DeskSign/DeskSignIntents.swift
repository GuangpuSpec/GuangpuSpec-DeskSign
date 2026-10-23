import AppIntents

// Change the sign without touching the tent: Siri, Shortcuts, Spotlight,
// an Action button, or a Shortcut run from your Mac or Watch.

struct DeskStatusEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Desk Status"
    static let defaultQuery = DeskStatusQuery()

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

struct DeskStatusQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [DeskStatusEntity] {
        await MainActor.run {
            StatusStore.shared.statuses
                .filter { identifiers.contains($0.id) }
                .map(DeskStatusEntity.init)
        }
    }

    func suggestedEntities() async throws -> [DeskStatusEntity] {
        await MainActor.run {
            StatusStore.shared.statuses.map(DeskStatusEntity.init)
        }
    }
}

struct SetDeskStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Desk Status"
    static let description = IntentDescription("Changes what the desk sign shows.")

    @Parameter(title: "Status")
    var status: DeskStatusEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { StatusStore.shared.select(status.id) }
        return .result(dialog: "Desk sign now says \(status.text).")
    }
}

struct NextDeskStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Desk Status"
    static let description = IntentDescription("Switches the desk sign to the next status.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run {
            StatusStore.shared.cycle()
            return StatusStore.shared.current?.text ?? ""
        }
        return .result(dialog: "Desk sign now says \(text).")
    }
}

struct DeskSignShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetDeskStatusIntent(),
            phrases: [
                "Set my \(.applicationName)",
                "Change my \(.applicationName)",
            ],
            shortTitle: "Set Status",
            systemImageName: "text.badge.checkmark"
        )
        AppShortcut(
            intent: NextDeskStatusIntent(),
            phrases: ["Next \(.applicationName) status"],
            shortTitle: "Next Status",
            systemImageName: "arrow.right.circle"
        )
    }
}
