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
                Button {
                    Task { await save(direction: .sourceToTarget) }
                } label: {
                    Label("Save \(env.defaultPair.source.uppercased()) → \(env.defaultPair.target.uppercased())",
                          systemImage: "plus.rectangle.on.rectangle")
                }
                Button {
                    Task { await save(direction: .targetToSource) }
                } label: {
                    Label("Save \(env.defaultPair.target.uppercased()) → \(env.defaultPair.source.uppercased())",
                          systemImage: "arrow.left.arrow.right.square")
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
    }

    private var exampleSelectionKey: String {
        "\(selectedSourceTermIdsArray)-\(selectedTargetTermIdsArray)"
    }

    private func loadExamples() async {
        isLoadingExamples = true
        examplesError = nil
        do {
            var seen = Set<Int64>()
            var matches: [ExampleSentence] = []
            for termId in selectedSourceTermIdsArray + selectedTargetTermIdsArray where termId != 0 {
                let termMatches = try await env.exampleSentenceService.examples(for: termId, limit: 3)
                for example in termMatches where seen.insert(example.id).inserted {
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

    private func save(direction: CardDirection) async {
        saveError = nil
        saveMessage = nil
        do {
            let deck = try await env.cardService.ensureDefaultDeck(for: env.defaultPair)
            let result = try await env.cardService.createCard(
                from: hit,
                direction: direction,
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
