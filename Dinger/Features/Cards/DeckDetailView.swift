import SwiftUI

struct DeckDetailView: View {
    let env: AppEnvironment
    let deck: Deck
    @State private var vm: DeckDetailViewModel

    init(env: AppEnvironment, deck: Deck) {
        self.env = env
        self.deck = deck
        _vm = State(wrappedValue: DeckDetailViewModel(service: env.cardService, database: env.database, deck: deck))
    }

    var body: some View {
        List {
            if vm.rows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Look up a word in the Dictionary tab and tap \"Save\".")
                    )
                }
            } else {
                ForEach(vm.rows) { row in
                    NavigationLink {
                        CardEditorView(env: env, row: row, onChanged: {
                            Task { await vm.reload() }
                        })
                    } label: {
                        cardRow(row)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.delete(row) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            Task { await vm.suspend(row) }
                        } label: {
                            Label(row.suspended ? "Unsuspend" : "Suspend",
                                  systemImage: row.suspended ? "play" : "pause")
                        }
                        .tint(.orange)
                    }
                }
            }
            if let err = vm.error {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .navigationTitle(deck.name)
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
    }

    private func cardRow(_ row: CardRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.frontSurface).font(.headline)
                if row.suspended {
                    Image(systemName: "pause.circle").foregroundStyle(.orange)
                }
                Spacer()
                Text(row.card.direction == .sourceToTarget ? "S→T" : "T→S")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(row.backSurface)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let due = row.dueAt {
                Text(dueLabel(for: due))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func dueLabel(for date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Due now" }
        let days = Int(interval / 86_400)
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days)d"
    }
}
