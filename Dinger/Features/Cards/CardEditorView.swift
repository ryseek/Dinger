import SwiftUI

struct CardEditorView: View {
    let env: AppEnvironment
    let onChanged: () -> Void

    @State private var card: Card
    @State private var dictionaryFrontSurfaces: [String]
    @State private var dictionaryBackSurfaces: [String]
    @State private var repetitions: Int
    @State private var dueAt: Date?
    @State private var suspended: Bool
    @State private var example: ExampleSentence?
    @State private var exampleError: String?
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment, row: CardRow, onChanged: @escaping () -> Void) {
        self.env = env
        self.onChanged = onChanged
        _card         = State(initialValue: row.card)
        _dictionaryFrontSurfaces = State(initialValue: row.dictionaryFrontSurfaces)
        _dictionaryBackSurfaces  = State(initialValue: row.dictionaryBackSurfaces)
        _repetitions  = State(initialValue: row.repetitions)
        _dueAt        = State(initialValue: row.dueAt)
        _suspended    = State(initialValue: row.suspended)
    }

    var body: some View {
        Form {
            Section("Front") {
                ForEach(Array(displayedFrontSurfaces.enumerated()), id: \.offset) { _, surface in
                    Text(surface).font(.title3)
                }
            }
            Section("Back") {
                ForEach(Array(displayedBackSurfaces.enumerated()), id: \.offset) { _, surface in
                    Text(surface).font(.body)
                }
            }
            if let example {
                Section("Example") {
                    CardExampleSentenceBlock(example: example, frontLanguageCode: frontLanguageCode)
                }
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
                NavigationLink {
                    CardContentEditorView(env: env, card: card) { updatedCard, hit in
                        applyUpdatedContent(updatedCard, hit: hit)
                    }
                } label: {
                    Label("Edit card", systemImage: "pencil")
                }
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
            if let exampleError {
                Section { Text(exampleError).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: exampleTaskKey) {
            await loadExample()
        }
    }

    private var exampleTaskKey: String {
        "\(card.id ?? 0)-\(card.frontTermIdsRaw)-\(card.backTermIdsRaw)-\(card.direction.rawValue)"
    }

    private var frontLanguageCode: String {
        card.direction == .sourceToTarget ? env.defaultPair.source : env.defaultPair.target
    }

    private var displayedFrontSurfaces: [String] {
        card.frontTextOverride.map { [$0] } ?? dictionaryFrontSurfaces
    }

    private var displayedBackSurfaces: [String] {
        card.backTextOverride.map { [$0] } ?? dictionaryBackSurfaces
    }

    private func applyUpdatedContent(_ updatedCard: Card, hit: SenseHit) {
        let sourceTermIds = updatedCard.direction == .sourceToTarget
            ? updatedCard.frontTermIds
            : updatedCard.backTermIds
        let targetTermIds = updatedCard.direction == .sourceToTarget
            ? updatedCard.backTermIds
            : updatedCard.frontTermIds
        let sourceSurfaces = hit.sourceTerms
            .filter { sourceTermIds.contains($0.termId) }
            .map(\.surface)
        let targetSurfaces = hit.targetTerms
            .filter { targetTermIds.contains($0.termId) }
            .map(\.surface)
        if updatedCard.direction == .sourceToTarget {
            dictionaryFrontSurfaces = sourceSurfaces
            dictionaryBackSurfaces = targetSurfaces
        } else {
            dictionaryFrontSurfaces = targetSurfaces
            dictionaryBackSurfaces = sourceSurfaces
        }
        card = updatedCard
        saveError = nil
        onChanged()
    }

    private func loadExample() async {
        do {
            example = try await env.exampleSentenceService.bestExample(for: card)
            exampleError = nil
        } catch {
            example = nil
            exampleError = error.localizedDescription
        }
    }

    private func invert() async {
        do {
            let updated = try await env.cardService.invert(card: card)
            swap(&dictionaryFrontSurfaces, &dictionaryBackSurfaces)
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

private struct CardContentEditorView: View {
    let env: AppEnvironment
    let card: Card
    let onSaved: (Card, SenseHit) -> Void

    @State private var hit: SenseHit?
    @State private var selectedSourceTermIds: Set<Int64>
    @State private var selectedTargetTermIds: Set<Int64>
    @State private var customFrontText: String
    @State private var customBackText: String
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment,
         card: Card,
         onSaved: @escaping (Card, SenseHit) -> Void) {
        self.env = env
        self.card = card
        self.onSaved = onSaved
        let sourceTermIds = card.direction == .sourceToTarget
            ? card.frontTermIds
            : card.backTermIds
        let targetTermIds = card.direction == .sourceToTarget
            ? card.backTermIds
            : card.frontTermIds
        _selectedSourceTermIds = State(initialValue: Set(sourceTermIds))
        _selectedTargetTermIds = State(initialValue: Set(targetTermIds))
        _customFrontText = State(initialValue: card.frontTextOverride ?? "")
        _customBackText = State(initialValue: card.backTextOverride ?? "")
    }

    var body: some View {
        Form {
            if isLoading {
                Section { ProgressView("Loading dictionary values…") }
            } else if let hit {
                Section("Source (\(env.defaultPair.source.uppercased()))") {
                    TermSelectionList(
                        terms: hit.sourceTerms,
                        selectedTermIds: $selectedSourceTermIds,
                        selectableLabel: "source variant"
                    )
                }
                Section("Target (\(env.defaultPair.target.uppercased()))") {
                    TermSelectionList(
                        terms: hit.targetTerms,
                        selectedTermIds: $selectedTargetTermIds,
                        selectableLabel: "translation variant"
                    )
                }
                Section("Custom text (optional)") {
                    TextField("Custom front", text: $customFrontText, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Custom back", text: $customBackText, axis: .vertical)
                        .lineLimit(1...4)
                    Text("Leave either field empty to use the selected dictionary values on that side.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !hit.domain.isEmpty || hit.context != nil {
                    Section("Notes") {
                        if !hit.domain.isEmpty {
                            LabeledContent("Domain", value: hit.domain.joined(separator: ", "))
                        }
                        if let context = hit.context {
                            LabeledContent("Context", value: context)
                        }
                    }
                }
                Section {
                    Button {
                        Task { await save(hit: hit) }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() }
                            Text("Save card")
                            Spacer()
                        }
                    }
                    .disabled(isSaving || selectedSourceTermIds.isEmpty || selectedTargetTermIds.isEmpty)
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Edit card")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSense() }
    }

    private func loadSense() async {
        isLoading = true
        error = nil
        do {
            guard let loadedHit = try await env.searchService.senseHit(
                senseId: card.senseId,
                matchedTermId: card.frontTermId,
                pair: env.defaultPair
            ) else {
                throw CardServiceError.senseNotFound
            }
            let sourceIds = Set(loadedHit.sourceTerms.map(\.termId))
            let targetIds = Set(loadedHit.targetTerms.map(\.termId))
            selectedSourceTermIds.formIntersection(sourceIds)
            selectedTargetTermIds.formIntersection(targetIds)
            if selectedSourceTermIds.isEmpty, let first = loadedHit.sourceTerms.first?.termId {
                selectedSourceTermIds.insert(first)
            }
            if selectedTargetTermIds.isEmpty, let first = loadedHit.targetTerms.first?.termId {
                selectedTargetTermIds.insert(first)
            }
            hit = loadedHit
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save(hit: SenseHit) async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let updated = try await env.cardService.updateCardContent(
                card: card,
                hit: hit,
                selectedSourceTermIds: orderedIds(from: hit.sourceTerms, selected: selectedSourceTermIds),
                selectedTargetTermIds: orderedIds(from: hit.targetTerms, selected: selectedTargetTermIds),
                frontTextOverride: customFrontText,
                backTextOverride: customBackText
            )
            onSaved(updated, hit)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func orderedIds(from terms: [TermDisplay], selected: Set<Int64>) -> [Int64] {
        terms.map(\.termId).filter { selected.contains($0) }
    }
}

private struct CardExampleSentenceBlock: View {
    let example: ExampleSentence
    let frontLanguageCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(example.text(for: frontLanguageCode))
                .font(.body)
            Text(example.text(for: frontLanguageCode == "de" ? "en" : "de"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}
