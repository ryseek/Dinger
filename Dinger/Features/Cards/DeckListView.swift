import SwiftUI
import UniformTypeIdentifiers

struct CardsRootView: View {
    let env: AppEnvironment
    @State private var vm: DeckListViewModel
    @State private var showNewDeck = false
    @State private var newDeckName = ""
    @State private var showImportDeck = false
    @State private var showRenameDeck = false
    @State private var deckToRename: Deck?
    @State private var renameDeckName = ""
    @State private var showExportDeck = false
    @State private var exportFilename = "deck"
    @State private var exportDocument = DeckJSONDocument(data: Data())

    init(env: AppEnvironment) {
        self.env = env
        _vm = State(wrappedValue: DeckListViewModel(service: env.cardService, pair: env.defaultPair))
    }

    var body: some View {
        NavigationStack {
            List {
                if vm.isAddingDeck {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(vm.deckAddStatus ?? "Adding deck...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let progress = vm.deckAddProgress {
                                ProgressView(value: progress)
                            } else {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                ForEach(vm.decks) { deck in
                    NavigationLink {
                        DeckDetailView(env: env, deck: deck)
                    } label: {
                        deckRow(deck)
                    }
                    .contextMenu {
                        Button {
                            beginRename(deck)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            export(deck)
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            Task { await vm.delete(deck) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.delete(deck) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            beginRename(deck)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                if let err = vm.error {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showImportDeck = true
                    } label: {
                        Label("Import Deck...", systemImage: "square.and.arrow.down")
                    }
                }
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
            .alert("Rename deck", isPresented: $showRenameDeck) {
                TextField("Deck name", text: $renameDeckName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let deck = deckToRename else { return }
                    let trimmed = renameDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await vm.rename(deck, to: trimmed) }
                }
            }
            .fileImporter(isPresented: $showImportDeck, allowedContentTypes: [.json]) { result in
                Task { await importDeck(result) }
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
    }

    private func deckRow(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deck.name).font(.headline)
            Text("\(deck.sourceLang.uppercased()) → \(deck.targetLang.uppercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func beginRename(_ deck: Deck) {
        deckToRename = deck
        renameDeckName = deck.name
        showRenameDeck = true
    }

    private func export(_ deck: Deck) {
        Task {
            guard let data = await vm.export(deck) else { return }
            exportDocument = DeckJSONDocument(data: data)
            exportFilename = exportFileName(for: deck)
            showExportDeck = true
        }
    }

    private func importDeck(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            await vm.importDeck(data: data)
        } catch {
            vm.setError(error.localizedDescription)
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

struct DeckJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
