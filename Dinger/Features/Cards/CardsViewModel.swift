import DingerCore
import Foundation
import Observation

@Observable
@MainActor
public final class DeckListViewModel {
    public var decks: [Deck] = []
    public var activity: StudyActivitySummary = .empty
    public var error: String?
    public var isAddingDeck = false
    public var deckAddProgress: Double?
    public var deckAddStatus: String?
    private let service: CardService
    private let insights: StudyInsightsService
    private let pair: LanguagePair

    public init(service: CardService, insights: StudyInsightsService, pair: LanguagePair) {
        self.service = service
        self.insights = insights
        self.pair = pair
    }

    public func reload() async {
        do {
            _ = try await service.ensureDefaultDeck(for: pair) // guarantee a default deck exists
            async let loadedDecks = service.allDecks()
            async let loadedActivity = insights.activity()
            (decks, activity) = try await (loadedDecks, loadedActivity)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func reloadActivity() async {
        do {
            activity = try await insights.activity()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func createDeck(name: String) async {
        beginDeckAdd(status: "Creating deck...", progress: nil)
        defer { finishDeckAdd() }
        do {
            _ = try await service.createDeck(name: name, pair: pair)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func rename(_ deck: Deck, to name: String) async {
        do {
            _ = try await service.renameDeck(deck, to: name)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func export(_ deck: Deck) async -> Data? {
        do {
            let data = try await service.exportDeck(deck)
            error = nil
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func exportAllDecks() async -> Data? {
        do {
            let data = try await service.exportAllDecks()
            error = nil
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func importDeck(data: Data) async {
        beginDeckAdd(status: "Importing deck or backup...", progress: 0)
        defer { finishDeckAdd() }
        do {
            _ = try await service.importDecks(from: data) { [weak self] progress in
                guard let self else { return }
                Task { @MainActor [self] in
                    self.deckAddProgress = progress
                }
            }
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func setError(_ message: String) {
        error = message
    }

    public func delete(_ deck: Deck) async {
        do {
            try await service.deleteDeck(deck)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func beginDeckAdd(status: String, progress: Double?) {
        isAddingDeck = true
        deckAddStatus = status
        deckAddProgress = progress
        error = nil
    }

    private func finishDeckAdd() {
        isAddingDeck = false
        deckAddStatus = nil
        deckAddProgress = nil
    }

}

@Observable
@MainActor
public final class DeckDetailViewModel {
    public var rows: [CardRow] = []
    public var statistics: DeckStatistics = .empty
    public var error: String?
    public private(set) var deck: Deck

    private let service: CardService
    private let insights: StudyInsightsService

    public init(service: CardService, insights: StudyInsightsService, deck: Deck) {
        self.service = service
        self.insights = insights
        self.deck = deck
    }

    public func reload() async {
        do {
            async let loadedRows = insights.cardRows(in: deck)
            async let loadedStatistics = insights.statistics(for: deck)
            (rows, statistics) = try await (loadedRows, loadedStatistics)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func suspend(_ row: CardRow) async {
        do {
            try await service.suspend(card: row.card, !row.suspended)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func delete(_ row: CardRow) async {
        do {
            try await service.delete(card: row.card)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func renameDeck(to name: String) async {
        do {
            deck = try await service.renameDeck(deck, to: name)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func exportDeck() async -> Data? {
        do {
            let data = try await service.exportDeck(deck)
            error = nil
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func setError(_ message: String) {
        error = message
    }

}
