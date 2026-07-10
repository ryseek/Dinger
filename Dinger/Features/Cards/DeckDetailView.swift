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
                progressSection
                if !vm.statistics.hardestCards.isEmpty {
                    hardestCardsSection
                }
                Section("Words") {
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

    private var progressSection: some View {
        Section("Deck Insights") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reviewed")
                    Spacer()
                    Text("\(vm.statistics.reviewedCards) of \(vm.statistics.totalCards)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: vm.statistics.reviewedFraction)
                    .tint(.blue)
            }
            .padding(.vertical, 4)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statTile("Due", value: vm.statistics.dueCards, icon: "clock", color: .orange)
                statTile("Tomorrow", value: vm.statistics.dueTomorrow, icon: "calendar.badge.clock", color: .orange)
                statTile("This Week", value: vm.statistics.reviewsThisWeek, icon: "calendar", color: .blue)
                statTile(
                    "Retention",
                    value: vm.statistics.retentionRate.formatted(.percent.precision(.fractionLength(0))),
                    icon: "brain.head.profile",
                    color: .teal
                )
                statTile("Reviews", value: vm.statistics.totalReviews, icon: "checkmark.circle", color: .blue)
                statTile("Repetitions", value: vm.statistics.totalRepetitions, icon: "repeat", color: .purple)
                statTile("Learning", value: vm.statistics.learningCards, icon: "book.pages", color: .indigo)
                statTile("Mature", value: vm.statistics.matureCards, icon: "star.fill", color: .green)
            }
            .padding(.vertical, 4)
        }
    }

    private var hardestCardsSection: some View {
        Section("Hardest Words") {
            ForEach(vm.statistics.hardestCards) { card in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.front).font(.headline)
                        Text(card.back).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(card.againCount) of \(card.reviewCount) missed")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }
        }
    }

    private func statTile(_ title: String, value: Int, icon: String, color: Color) -> some View {
        statTile(title, value: value.formatted(), icon: icon, color: color)
    }

    private func statTile(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
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
