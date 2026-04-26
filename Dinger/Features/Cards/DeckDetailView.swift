import SwiftUI
import UniformTypeIdentifiers

struct DeckDetailView: View {
    let env: AppEnvironment
    let deck: Deck
    @State private var vm: DeckDetailViewModel
    @State private var showRenameDeck = false
    @State private var renameDeckName = ""
    @State private var showExportDeck = false
    @State private var exportFilename = "deck"
    @State private var exportDocument = DeckJSONDocument(data: Data())

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
        .navigationTitle(vm.deck.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        renameDeckName = vm.deck.name
                        showRenameDeck = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        exportDeck()
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Deck Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename deck", isPresented: $showRenameDeck) {
            TextField("Deck name", text: $renameDeckName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = renameDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { await vm.renameDeck(to: trimmed) }
            }
        }
        .fileExporter(isPresented: $showExportDeck,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: exportFilename) { result in
            if case .failure(let error) = result {
                vm.setError(error.localizedDescription)
            }
        }
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
    }

    private func cardRow(_ row: CardRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.frontSurfaces.joined(separator: " / ")).font(.headline)
                if row.suspended {
                    Image(systemName: "pause.circle").foregroundStyle(.orange)
                }
                Spacer()
                Text(row.card.direction == .sourceToTarget ? "S→T" : "T→S")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(row.backSurfaces.joined(separator: " / "))
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

    private func exportDeck() {
        Task {
            guard let data = await vm.exportDeck() else { return }
            exportDocument = DeckJSONDocument(data: data)
            exportFilename = exportFileName(for: vm.deck)
            showExportDeck = true
        }
    }

    private func exportFileName(for deck: Deck) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = deck.name
            .lowercased()
            .map { character -> Character in
                character.unicodeScalars.allSatisfy { allowed.contains($0) } ? character : "-"
            }
        let collapsed = String(slug).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "deck" : "\(collapsed)-deck"
    }
}
