import SwiftUI

struct EntryDetailView: View {
    let env: AppEnvironment
    let hit: SenseHit
    let recordHistory: Bool
    let onHistoryRecorded: (() async -> Void)?

    @State private var selectedSourceTermIds: Set<Int64> = []
    @State private var selectedTargetTermIds: Set<Int64> = []
    @State private var examples: [ExampleSentence] = []
    @State private var examplesError: String?
    @State private var isLoadingExamples = false
    @State private var saveMessage: String?
    @State private var saveError: String?
    @State private var decks: [Deck] = []
    @State private var selectedDeckId: Int64?
    @State private var isLoadingDecks = false

    init(env: AppEnvironment,
         hit: SenseHit,
         recordHistory: Bool = true,
         onHistoryRecorded: (() async -> Void)? = nil) {
        self.env = env
        self.hit = hit
        self.recordHistory = recordHistory
        self.onHistoryRecorded = onHistoryRecorded
    }

    var body: some View {
        List {
            Section("Source (\(env.defaultPair.source.uppercased()))") {
                TermSelectionList(
                    terms: hit.sourceTerms,
                    selectedTermIds: selectedSourceTermBinding,
                    selectableLabel: "source variant"
                )
            }
            Section("Target (\(env.defaultPair.target.uppercased()))") {
                TermSelectionList(
                    terms: hit.targetTerms,
                    selectedTermIds: selectedTargetTermBinding,
                    selectableLabel: "translation variant"
                )
            }
            if !hit.domain.isEmpty || hit.context != nil {
                Section("Notes") {
                    if !hit.domain.isEmpty {
                        LabeledContent("Domain", value: hit.domain.joined(separator: ", "))
                    }
                    if let ctx = hit.context {
                        LabeledContent("Context", value: ctx)
                    }
                }
            }
            if isLoadingExamples || !examples.isEmpty || examplesError != nil {
                Section("Examples") {
                    if isLoadingExamples {
                        ProgressView()
                    }
                    ForEach(examples) { example in
                        ExampleSentenceBlock(example: example)
                    }
                    if let examplesError {
                        Text(examplesError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            Section("Save to deck") {
                if isLoadingDecks {
                    ProgressView()
                } else if decks.isEmpty {
                    Text("No decks available.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Deck", selection: Binding(
                        get: { selectedDeckId ?? decks.first?.id ?? -1 },
                        set: { newId in
                            selectedDeckId = newId
                            env.lastUsedDeckId = newId
                            saveMessage = nil
                            saveError = nil
                        }
                    )) {
                        ForEach(decks) { deck in
                            Text(deck.name).tag(deck.id ?? -1)
                        }
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        Label("Save to deck", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .disabled(selectedDeck == nil)
                }
                if let msg = saveMessage {
                    Text(msg).font(.footnote).foregroundStyle(.green)
                }
                if let err = saveError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(hit.sourceTerms.first?.headword ?? "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard recordHistory else { return }
            try? await env.historyService.recordOpenedSense(hit: hit, pair: env.defaultPair)
            await onHistoryRecorded?()
        }
        .task(id: exampleSelectionKey) {
            await loadExamples()
        }
        .task {
            await loadDecks()
        }
    }

    private var exampleSelectionKey: String {
        "\(selectedSourceTermIdsArray)-\(selectedTargetTermIdsArray)"
    }

    private var selectedDeck: Deck? {
        guard let selectedDeckId else { return decks.first }
        return decks.first { $0.id == selectedDeckId }
    }

    private func loadExamples() async {
        isLoadingExamples = true
        examplesError = nil
        do {
            var seenIds = Set<Int64>()
            var seenGermanTexts = Set<String>()
            var seenEnglishTexts = Set<String>()
            var matches: [ExampleSentence] = []
            for termId in selectedSourceTermIdsArray + selectedTargetTermIdsArray where termId != 0 {
                let termMatches = try await env.exampleSentenceService.examples(for: termId, limit: 3)
                for example in termMatches
                    where seenIds.insert(example.id).inserted
                    && seenGermanTexts.insert(TextNormalizer.normalize(example.germanText)).inserted
                    && seenEnglishTexts.insert(TextNormalizer.normalize(example.englishText)).inserted {
                    matches.append(example)
                    if matches.count >= 3 { break }
                }
                if matches.count >= 3 { break }
            }
            examples = matches
            isLoadingExamples = false
        } catch {
            examples = []
            examplesError = error.localizedDescription
            isLoadingExamples = false
        }
    }

    private func loadDecks() async {
        isLoadingDecks = true
        saveError = nil
        do {
            _ = try await env.cardService.ensureDefaultDeck(for: env.defaultPair)
            decks = try await env.cardService.allDecks()
            if let lastUsedDeckId = env.lastUsedDeckId,
               decks.contains(where: { $0.id == lastUsedDeckId }) {
                selectedDeckId = lastUsedDeckId
            } else {
                selectedDeckId = decks.first?.id
                env.lastUsedDeckId = selectedDeckId
            }
            isLoadingDecks = false
        } catch {
            decks = []
            isLoadingDecks = false
            saveError = error.localizedDescription
        }
    }

    private func save() async {
        saveError = nil
        saveMessage = nil
        do {
            guard let deck = selectedDeck else {
                throw CardServiceError.invalidDeckFile
            }
            env.lastUsedDeckId = deck.id
            let result = try await env.cardService.createCard(
                from: hit,
                direction: .sourceToTarget,
                deck: deck,
                selectedSourceTermIds: selectedSourceTermIdsArray,
                selectedTargetTermIds: selectedTargetTermIdsArray
            )
            if result.isNew {
                saveMessage = "Added to \(deck.name)."
            } else if result.didUpdate {
                saveMessage = "Updated in \(deck.name)."
            } else {
                saveMessage = "Already in \(deck.name)."
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var selectedSourceTermIdsArray: [Int64] {
        orderedSelectedIds(from: hit.sourceTerms, selectedIds: selectedSourceTermBinding.wrappedValue)
    }

    private var selectedTargetTermIdsArray: [Int64] {
        orderedSelectedIds(from: hit.targetTerms, selectedIds: selectedTargetTermBinding.wrappedValue)
    }

    private func orderedSelectedIds(from terms: [TermDisplay], selectedIds: Set<Int64>) -> [Int64] {
        terms.map(\.termId).filter { selectedIds.contains($0) }
    }

    private var selectedSourceTermBinding: Binding<Set<Int64>> {
        Binding {
            selectedSourceTermIds.isEmpty ? Set(hit.sourceTerms.prefix(1).map(\.termId)) : selectedSourceTermIds
        } set: { newValue in
            selectedSourceTermIds = newValue
        }
    }

    private var selectedTargetTermBinding: Binding<Set<Int64>> {
        Binding {
            selectedTargetTermIds.isEmpty ? Set(hit.targetTerms.prefix(1).map(\.termId)) : selectedTargetTermIds
        } set: { newValue in
            selectedTargetTermIds = newValue
        }
    }
}

private struct TermSelectionList: View {
    let terms: [TermDisplay]
    @Binding var selectedTermIds: Set<Int64>
    let selectableLabel: String

    var body: some View {
        if terms.count <= 1 {
            ForEach(terms, id: \.termId) { term in
                TermLine(term: term)
            }
        } else {
            ForEach(terms, id: \.termId) { term in
                Button {
                    toggle(term.termId)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TermLine(term: term)
                        Spacer()
                        if selectedTermIds.contains(term.termId) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Selected \(selectableLabel)")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ termId: Int64) {
        if selectedTermIds.contains(termId) {
            guard selectedTermIds.count > 1 else { return }
            selectedTermIds.remove(termId)
        } else {
            selectedTermIds.insert(termId)
        }
    }
}

private struct TermLine: View {
    let term: TermDisplay
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(term.surface)
                .font(.body)
            Spacer()
            if let g = term.gender {
                Text("{\(g)}").font(.caption).foregroundStyle(.secondary)
            }
            if let p = term.pos {
                Text("{\(p)}").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ExampleSentenceBlock: View {
    let example: ExampleSentence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(example.germanText)
                .font(.body)
            Text(example.englishText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}
