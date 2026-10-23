import DuoKit
import SwiftUI

/// Write a status and choose how it looks. Cancel and Save are system toolbar items.
struct StatusEditor: View {
    let original: DeskStatus
    let onSave: (DeskStatus) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: DeskStatus

    init(original: DeskStatus, onSave: @escaping (DeskStatus) -> Void) {
        self.original = original
        self.onSave = onSave
        _draft = State(initialValue: original)
    }

    private var trimmed: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SignView(status: previewStatus)
                        .frame(height: 140)
                        .clipShape(.rect(cornerRadius: 14))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Message") {
                    TextField("IN A MEETING WITH MY BED", text: $draft.text, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.characters)
                }

                Section("Style") {
                    Picker("Style", selection: $draft.style) {
                        ForEach(SignStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Animation") {
                    // Live previews: every motion plays with your text and style.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: Duo.Space.m)],
                              spacing: Duo.Space.l) {
                        ForEach(SignAnimation.allCases) { motion in
                            motionTile(motion)
                        }
                    }
                    .padding(.vertical, Duo.Space.s)
                }
            }
            .navigationTitle(original.text.isEmpty
                             ? String(localized: "New Status")
                             : String(localized: "Edit Status"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        var saved = draft
                        saved.text = trimmed
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
    }

    private func motionTile(_ motion: SignAnimation) -> some View {
        let selected = draft.animation == motion
        return Button {
            draft.animation = motion
        } label: {
            VStack(spacing: Duo.Space.s) {
                SignView(status: DeskStatus(text: previewStatus.text, style: draft.style, animation: motion))
                    .frame(height: 56)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Duo.sun : .clear, lineWidth: 3)
                    }
                Text(motion.label)
                    .font(selected ? DuoType.footnote.weight(.semibold) : DuoType.footnote)
                    .foregroundStyle(selected ? Duo.ink : Duo.ink3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(motion.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Preview shows placeholder text until something is typed.
    private var previewStatus: DeskStatus {
        var s = draft
        if trimmed.isEmpty { s.text = String(localized: "YOUR MESSAGE") }
        return s
    }
}
