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
    @State private var selectedInsight: DeckInsight?

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
        .navigationDestination(item: $selectedInsight) { insight in
            insightDetail(insight)
        }
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
    }

    private var progressSection: some View {
        Section("Deck Insights") {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    insightDetail(.reviewed)
                } label: {
                    HStack {
                        Text("Reviewed")
                        Spacer()
                        Text("\(vm.statistics.reviewedCards) of \(vm.statistics.totalCards)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                ProgressView(value: vm.statistics.reviewedFraction)
                    .tint(.blue)
            }
            .padding(.vertical, 4)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statLink(.due, value: vm.statistics.dueCards, icon: "clock", color: .orange)
                statLink(.tomorrow, value: vm.statistics.dueTomorrow, icon: "calendar.badge.clock", color: .orange)
                statLink(.thisWeek, value: vm.statistics.reviewsThisWeek, icon: "calendar", color: .blue)
                statLink(
                    .retention,
                    "Retention",
                    value: vm.statistics.retentionRate.formatted(.percent.precision(.fractionLength(0))),
                    icon: "brain.head.profile",
                    color: .teal
                )
                statLink(.reviews, value: vm.statistics.totalReviews, icon: "checkmark.circle", color: .blue)
                statLink(.repetitions, value: vm.statistics.totalRepetitions, icon: "repeat", color: .purple)
                statLink(.learning, value: vm.statistics.learningCards, icon: "book.pages", color: .indigo)
                statLink(.mature, value: vm.statistics.matureCards, icon: "star.fill", color: .green)
            }
            .padding(.vertical, 4)
        }
    }

    private func insightDetail(_ insight: DeckInsight) -> some View {
        DeckInsightDetailView(
            insight: insight,
            rows: insight.rows(from: vm.rows),
            env: env,
            onChanged: { Task { await vm.reload() } }
        )
    }

    private func statLink(_ insight: DeckInsight, value: Int, icon: String, color: Color) -> some View {
        statLink(insight, insight.tileTitle, value: value.formatted(), icon: icon, color: color)
    }

    private func statLink(_ insight: DeckInsight, _ title: String, value: String, icon: String, color: Color) -> some View {
        Button {
            selectedInsight = insight
        } label: {
            statTile(title, value: value, icon: icon, color: color)
        }
        .buttonStyle(.plain)
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

private enum DeckInsight: String, Identifiable, Hashable {
    case reviewed, due, tomorrow, thisWeek, retention, reviews, repetitions, learning, mature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reviewed: "Reviewed Words"
        case .due: "Due Words"
        case .tomorrow: "Due Tomorrow"
        case .thisWeek: "Reviewed This Week"
        case .retention: "Retention by Word"
        case .reviews: "Review History"
        case .repetitions: "Repetitions by Word"
        case .learning: "Learning Words"
        case .mature: "Mature Words"
        }
    }

    var tileTitle: String {
        switch self {
        case .reviewed: "Reviewed"
        case .due: "Due"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "This Week"
        case .retention: "Retention"
        case .reviews: "Reviews"
        case .repetitions: "Repetitions"
        case .learning: "Learning"
        case .mature: "Mature"
        }
    }

    var emptyMessage: String {
        switch self {
        case .mature: "No words are mature yet. A word becomes mature at a 21-day interval."
        case .learning: "No words are currently being learned."
        case .due: "No words are due right now."
        case .tomorrow: "No words are due tomorrow."
        case .thisWeek: "No words have been reviewed this week."
        default: "No reviewed words to show yet."
        }
    }

    func rows(from rows: [CardRow], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [CardRow] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) ?? now
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? .distantPast

        return rows.filter { row in
            switch self {
            case .reviewed, .retention, .reviews:
                row.lastReviewedAt != nil
            case .due:
                !row.suspended && row.lastReviewedAt != nil && (row.dueAt ?? .distantFuture) <= now
            case .tomorrow:
                !row.suspended && row.lastReviewedAt != nil && (row.dueAt ?? .distantPast) >= tomorrow && (row.dueAt ?? .distantFuture) < dayAfterTomorrow
            case .thisWeek:
                (row.lastReviewedAt ?? .distantPast) >= weekAgo
            case .repetitions:
                row.repetitions > 0
            case .learning:
                row.lastReviewedAt != nil && row.intervalDays < 21
            case .mature:
                row.lastReviewedAt != nil && row.intervalDays >= 21
            }
        }.sorted { lhs, rhs in
            switch self {
            case .mature: lhs.intervalDays > rhs.intervalDays
            case .repetitions: lhs.repetitions > rhs.repetitions
            case .reviews, .retention: lhs.reviewCount > rhs.reviewCount
            default: (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
            }
        }
    }

    func detail(for row: CardRow) -> String {
        switch self {
        case .reviewed, .thisWeek:
            return row.lastReviewedAt.map { "Last reviewed \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        case .due, .tomorrow:
            return row.dueAt.map { "Due \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
        case .retention:
            let rate = row.reviewCount == 0 ? 0 : Double(row.successfulReviewCount) / Double(row.reviewCount)
            return "\(rate.formatted(.percent.precision(.fractionLength(0)))) retention · \(row.reviewCount) reviews"
        case .reviews:
            return "\(row.reviewCount) \(row.reviewCount == 1 ? "review" : "reviews")"
        case .repetitions:
            return "\(row.repetitions) \(row.repetitions == 1 ? "repetition" : "repetitions")"
        case .learning, .mature:
            return "\(row.intervalDays)-day interval · \(row.repetitions) repetitions"
        }
    }
}

private struct DeckInsightDetailView: View {
    let insight: DeckInsight
    let rows: [CardRow]
    let env: AppEnvironment
    let onChanged: () -> Void

    var body: some View {
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    insight.title,
                    systemImage: "rectangle.stack",
                    description: Text(insight.emptyMessage)
                )
            } else {
                Section("\(rows.count) \(rows.count == 1 ? "word" : "words")") {
                    ForEach(rows) { row in
                        NavigationLink {
                            CardEditorView(env: env, row: row, onChanged: onChanged)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.frontSurfaces.joined(separator: " / ")).font(.headline)
                                Text(row.backSurfaces.joined(separator: " / "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(insight.detail(for: row))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(insight.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
