import Foundation
import Observation
import GRDB

@Observable
@MainActor
public final class DeckListViewModel {
    public var decks: [Deck] = []
    public var error: String?
    private let service: CardService
    private let pair: LanguagePair

    public init(service: CardService, pair: LanguagePair) {
        self.service = service
        self.pair = pair
    }

    public func reload() async {
        do {
            _ = try await service.ensureDefaultDeck(for: pair) // guarantee a default deck exists
            decks = try await service.allDecks()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func createDeck(name: String) async {
        do {
            _ = try await service.createDeck(name: name, pair: pair)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func delete(_ deck: Deck) async {
        do {
            try await service.deleteDeck(deck)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public struct CardRow: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let card: Card
    public let frontSurfaces: [String]
    public let backSurfaces: [String]
    public let dueAt: Date?
    public let repetitions: Int
    public let suspended: Bool

    public var frontSurface: String {
        frontSurfaces.first ?? "?"
    }

    public var backSurface: String {
        backSurfaces.first ?? "?"
    }
}

@Observable
@MainActor
public final class DeckDetailViewModel {
    public var rows: [CardRow] = []
    public var error: String?
    public let deck: Deck

    private let service: CardService
    private let database: AppDatabase

    public init(service: CardService, database: AppDatabase, deck: Deck) {
        self.service = service
        self.database = database
        self.deck = deck
    }

    public func reload() async {
        do {
            rows = try await fetchRows()
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

    /// Fetch decorated rows off the writer queue.
    private func fetchRows() async throws -> [CardRow] {
        guard let deckId = deck.id else { return [] }
        return try await database.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.*,
                       tf.surface AS front_surface,
                       tb.surface AS back_surface,
                       s.due_at   AS due_at,
                       s.repetitions AS repetitions
                  FROM card c
                  LEFT JOIN term tf ON tf.id = c.front_term_id
                  LEFT JOIN term tb ON tb.id = c.back_term_id
                  LEFT JOIN card_srs s ON s.card_id = c.id
                 WHERE c.deck_id = ?
                 ORDER BY c.created_at DESC
                """, arguments: [deckId])
            return try rows.map { row -> CardRow in
                let card = Card(
                    id: row["id"],
                    deckId: row["deck_id"],
                    senseId: row["sense_id"],
                    frontTermId: row["front_term_id"],
                    backTermId: row["back_term_id"],
                    frontTermIds: Card.decodeTermIds(row["front_term_ids"] ?? ""),
                    backTermIds: Card.decodeTermIds(row["back_term_ids"] ?? ""),
                    direction: CardDirection(rawValue: row["direction"]) ?? .sourceToTarget,
                    createdAt: row["created_at"],
                    suspended: (row["suspended"] as Int? ?? 0) != 0
                )
                let frontSurfaces = try Self.termSurfaces(db: db, termIds: card.frontTermIds)
                let backSurfaces = try Self.termSurfaces(db: db, termIds: card.backTermIds)
                return CardRow(
                    id: card.id ?? 0,
                    card: card,
                    frontSurfaces: frontSurfaces.isEmpty ? [row["front_surface"] ?? "?"] : frontSurfaces,
                    backSurfaces: backSurfaces.isEmpty ? [row["back_surface"] ?? "?"] : backSurfaces,
                    dueAt: row["due_at"],
                    repetitions: row["repetitions"] ?? 0,
                    suspended: card.suspended
                )
            }
        }
    }

    private nonisolated static func termSurfaces(db: Database, termIds: [Int64]) throws -> [String] {
        guard !termIds.isEmpty else { return [] }
        let surfacesById = try termIds.reduce(into: [Int64: String]()) { result, termId in
            if let surface = try String.fetchOne(db, sql: "SELECT surface FROM term WHERE id = ?", arguments: [termId]) {
                result[termId] = surface
            }
        }
        return termIds.compactMap { surfacesById[$0] }
    }
}
