import SwiftUI
import DuoKit

@main
struct DeskSignApp: App {
    @State private var store = StatusStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Duo.ink)
        }
        .onChange(of: scenePhase) { _, phase in
            // A tap on the StandBy widget may have changed the status meanwhile.
            if phase == .active { store.reloadFromDisk() }
        }
    }
}
