import SwiftUI

struct CardEditorView: View {
    let env: AppEnvironment
    let onChanged: () -> Void

    @State private var card: Card
    @State private var frontSurface: String
    @State private var backSurface: String
    @State private var repetitions: Int
    @State private var dueAt: Date?
    @State private var suspended: Bool
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment, row: CardRow, onChanged: @escaping () -> Void) {
        self.env = env
        self.onChanged = onChanged
        _card         = State(initialValue: row.card)
        _frontSurface = State(initialValue: row.frontSurface)
        _backSurface  = State(initialValue: row.backSurface)
        _repetitions  = State(initialValue: row.repetitions)
        _dueAt        = State(initialValue: row.dueAt)
        _suspended    = State(initialValue: row.suspended)
    }

    var body: some View {
        Form {
            Section("Front") {
                Text(frontSurface).font(.title3)
            }
            Section("Back") {
                Text(backSurface).font(.body)
            }
            Section("Meta") {
                LabeledContent("Direction",
                               value: card.direction == .sourceToTarget ? "source → target" : "target → source")
                LabeledContent("Reps", value: "\(repetitions)")
                if let due = dueAt {
                    LabeledContent("Due", value: due.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section {
                Button {
                    Task { await invert() }
                } label: {
                    Label("Swap front and back", systemImage: "arrow.left.arrow.right")
                }
                Toggle("Suspended", isOn: $suspended)
                    .onChange(of: suspended) { _, newValue in
                        Task { await setSuspended(newValue) }
                    }
                Button(role: .destructive) {
                    Task { await delete() }
                } label: {
                    Label("Delete card", systemImage: "trash")
                }
            }
            if let err = saveError {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func invert() async {
        do {
            let updated = try await env.cardService.invert(card: card)
            swap(&frontSurface, &backSurface)
            card = updated
            saveError = nil
            onChanged()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func setSuspended(_ newValue: Bool) async {
        do {
            try await env.cardService.suspend(card: card, newValue)
            onChanged()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete() async {
        do {
            try await env.cardService.delete(card: card)
            onChanged()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
