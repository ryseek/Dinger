import SwiftUI

struct CardsRootView: View {
    let env: AppEnvironment
    @State private var vm: DeckListViewModel
    @State private var showNewDeck = false
    @State private var newDeckName = ""

    init(env: AppEnvironment) {
        self.env = env
        _vm = State(wrappedValue: DeckListViewModel(service: env.cardService, pair: env.defaultPair))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.decks) { deck in
                    NavigationLink {
                        DeckDetailView(env: env, deck: deck)
                    } label: {
                        deckRow(deck)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.delete(deck) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                if let err = vm.error {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newDeckName = ""
                        showNewDeck = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .alert("New deck", isPresented: $showNewDeck) {
                TextField("Deck name", text: $newDeckName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let trimmed = newDeckName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    Task { await vm.createDeck(name: trimmed) }
                }
            } message: {
                Text("For \(env.defaultPair.displayLabel)")
            }
            .task { await vm.reload() }
            .refreshable { await vm.reload() }
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deck.name).font(.headline)
            Text("\(deck.sourceLang.uppercased()) → \(deck.targetLang.uppercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
