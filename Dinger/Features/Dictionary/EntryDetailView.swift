import SwiftUI

struct EntryDetailView: View {
    let env: AppEnvironment
    let hit: SenseHit
    let recordHistory: Bool
    let onHistoryRecorded: (() async -> Void)?

    @State private var selectedSourceTermId: Int64?
    @State private var selectedTargetTermId: Int64?
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
                    selectedTermId: selectedSourceTermBinding,
                    selectableLabel: "source variant"
                )
            }
            Section("Target (\(env.defaultPair.target.uppercased()))") {
                TermSelectionList(
                    terms: hit.targetTerms,
                    selectedTermId: selectedTargetTermBinding,
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
                selectedSourceTermId: selectedSourceTermBinding.wrappedValue,
                selectedTargetTermId: selectedTargetTermBinding.wrappedValue
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

    private var selectedSourceTermBinding: Binding<Int64> {
        Binding {
            selectedSourceTermId ?? hit.sourceTerms.first?.termId ?? 0
        } set: { newValue in
            selectedSourceTermId = newValue
        }
    }

    private var selectedTargetTermBinding: Binding<Int64> {
        Binding {
            selectedTargetTermId ?? hit.targetTerms.first?.termId ?? 0
        } set: { newValue in
            selectedTargetTermId = newValue
        }
    }
}

private struct TermSelectionList: View {
    let terms: [TermDisplay]
    @Binding var selectedTermId: Int64
    let selectableLabel: String

    var body: some View {
        if terms.count <= 1 {
            ForEach(terms, id: \.termId) { term in
                TermLine(term: term)
            }
        } else {
            ForEach(terms, id: \.termId) { term in
                Button {
                    selectedTermId = term.termId
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TermLine(term: term)
                        Spacer()
                        if selectedTermId == term.termId {
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
