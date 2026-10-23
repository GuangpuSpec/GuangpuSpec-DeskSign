import DuoKit
import SwiftUI

/// How the app works:
/// - Phone in hand: tap a status to put it on the sign. Show Sign, New, Edit,
///   Reorder and StandBy setup are system toolbar items.
/// - Closed or tent mode (or Show Sign): the selected status fills the whole
///   outer screen, edge to edge, no status bar. Double-tap to switch; tap
///   once to show or hide the toolbar. Statuses in that toolbar opens the
///   list on the outer screen.
struct RootView: View {
    @Environment(StatusStore.self) private var store
    @State private var monitor = HingeMonitor()
    @State private var previewing = false
    /// Browsing the list on the outer screen instead of showing the sign.
    @State private var browsing = false
    @State private var editing: DeskStatus?
    /// Lives here, not in SignStage, so switching status never resets it.
    @State private var signControls = false

    private var onOuterDisplay: Bool {
        monitor.pose == .closed || monitor.pose == .tent
    }

    private var showSign: Bool {
        previewing || (onOuterDisplay && !browsing)
    }

    var body: some View {
        Group {
            if showSign, let status = store.current {
                NavigationStack {
                    SignStage(status: status, previewing: $previewing, showControls: $signControls,
                              onBrowse: onOuterDisplay && !previewing ? { browsing = true } : nil,
                              onEdit: { editing = status })
                }
            } else {
                // System tabs: a floating bar at the bottom in portrait, the
                // lower half of the vertical bar on the side.
                TabView {
                    Tab("Statuses", systemImage: "list.bullet") {
                        NavigationStack {
                            StatusListView(onShowSign: {
                                if onOuterDisplay { browsing = false } else { previewing = true }
                            }, onEdit: { editing = $0 })
                        }
                    }
                    Tab("StandBy", systemImage: "platter.filled.bottom.iphone") {
                        StandByGuide(inTab: true)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSign)
        // Any fold or unfold ends a manual preview, so the sign never gets stuck.
        .onChange(of: monitor.pose) {
            previewing = false
            browsing = false
        }
        .sheet(item: $editing) { status in
            StatusEditor(original: status) { store.upsert($0) }
        }
        .readsHinge(into: monitor)
    }
}

/// The sign, plus the "it's on a desk" behaviour: no auto-lock, double-tap to
/// cycle, tap to show the toolbar, dim after a while.
private struct SignStage: View {
    let status: DeskStatus
    @Binding var previewing: Bool
    @Binding var showControls: Bool
    /// Set on the outer screen: go to the list without unfolding.
    let onBrowse: (() -> Void)?
    let onEdit: () -> Void
    @Environment(StatusStore.self) private var store

    @State private var lastTouch = Date()
    @State private var dimmed = false
    /// Dim after this long without a touch.
    private let dimAfter: Duration = .seconds(10 * 60)

    var body: some View {
        ZStack {
            // The sign runs edge to edge, under the camera and the status bar.
            // It draws only; it takes no touches.
            SignView(status: status, isLive: true)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Color.black
                .opacity(dimmed ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            // Touches land on this layer, which stays inside the safe area.
            // Covering the region under the vertical bar would swallow the
            // bar's button taps.
            Color.clear
                .contentShape(.rect)
                .onTapGesture(count: 2) {
                    wake()
                    withAnimation(.snappy) { store.cycle() }
                }
                .onTapGesture {
                    wake()
                    withAnimation(.snappy) { showControls.toggle() }
                }
        }
            .toolbar {
                if previewing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { previewing = false }
                    }
                }
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("Next Status", systemImage: "arrow.down") {
                        wake()
                        withAnimation(.snappy) { store.cycle() }
                    }
                }
                if let onBrowse {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Statuses", systemImage: "list.bullet") {
                            showControls = false
                            onBrowse()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit", systemImage: "pencil") {
                        showControls = false
                        onEdit()
                    }
                }
            }
            .toolbarVisibility(showControls ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .task(id: lastTouch) {
                try? await Task.sleep(for: dimAfter)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 2)) { dimmed = true }
            }
            .task(id: ControlsTimer(shown: showControls, lastTouch: lastTouch)) {
                // The toolbar tucks itself away so it doesn't sit beside the
                // sign. Every touch (including a toolbar tap) restarts the wait.
                guard showControls else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { showControls = false }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .sensoryFeedback(.selection, trigger: status.id)
            .accessibilityLabel(status.text)
            .accessibilityHint("Double-tap to show the next status.")
    }

    private struct ControlsTimer: Equatable {
        let shown: Bool
        let lastTouch: Date
    }

    private func wake() {
        lastTouch = Date()
        if dimmed { withAnimation(.easeOut(duration: 0.3)) { dimmed = false } }
    }
}

/// The current sign up top, the statuses to pick from below.
private struct StatusListView: View {
    @Environment(StatusStore.self) private var store
    let onShowSign: () -> Void
    let onEdit: (DeskStatus) -> Void

    @State private var editMode: EditMode = .inactive
    @State private var confirmRestore = false

    var body: some View {
        List {
            if let current = store.current {
                Section {
                    SignView(status: current)
                        .frame(height: 150)
                        .clipShape(.rect(cornerRadius: 14))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityLabel(current.text)
                } footer: {
                    Text("Fold into a tent and this status fills the outer screen.")
                }
            }
            Section("Statuses") {
                ForEach(store.statuses) { status in
                    row(status)
                }
                .onDelete { store.delete(at: $0) }
                .onMove { store.move(from: $0, to: $1) }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Desk Sign")
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("Done", systemImage: "checkmark") { withAnimation { editMode = .inactive } }
                }
            } else {
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("Show Sign", systemImage: "rectangle.inset.filled", action: onShowSign)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("New Status", systemImage: "plus") {
                        onEdit(DeskStatus(text: "", style: .neon, animation: .none))
                    }
                    Button("Edit Status", systemImage: "pencil") {
                        if let current = store.current { onEdit(current) }
                    }
                    Button("Reorder", systemImage: "arrow.up.arrow.down") { withAnimation { editMode = .active } }
                }
            }
            ToolbarOverflowMenu {
                Button("Restore Presets", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmRestore = true
                }
            }
        }
        .confirmationDialog("Replace all statuses with the presets?",
                            isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore Presets", role: .destructive) { store.restorePresets() }
        }
    }

    private func row(_ status: DeskStatus) -> some View {
        let selected = status.id == store.current?.id
        return Button {
            store.select(status.id)
        } label: {
            HStack(spacing: Duo.Space.l) {
                SignView(status: status)
                    .frame(width: 104, height: 48)
                    .clipShape(.rect(cornerRadius: 8))
                Text(status.text)
                    .font(selected ? DuoType.headline : DuoType.body)
                    .foregroundStyle(Duo.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Duo.ink)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Setting up the StandBy widget, once.
private struct StandByGuide: View {
    /// Shown as a tab (large title, no Done) rather than a sheet.
    var inTab = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    step(1, "Lock iPhone Duo and stand it in tent mode. StandBy turns on.")
                    step(2, "Swipe to the widgets view, then touch and hold a widget stack.")
                    step(3, "Tap + and choose Desk Sign. Pick a size and add it.")
                    step(4, "Turn off Smart Rotate for that stack (or remove the other widgets) so the sign stays on screen.")
                } header: {
                    Text("Stand iPhone Duo in tent mode and StandBy shows your sign in LED letters.")
                        .textCase(nil)
                } footer: {
                    Text("From then on, whenever StandBy turns on, the sign is there. No need to open the app.")
                }
            }
            .navigationTitle("StandBy Widget")
            .navigationBarTitleDisplayMode(inTab ? .automatic : .inline)
            .toolbar {
                if !inTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Duo.Space.m) {
            Text(verbatim: "\(n)")
                .font(DuoType.headline.monospacedDigit())
                .foregroundStyle(Duo.ink3)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(DuoType.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
