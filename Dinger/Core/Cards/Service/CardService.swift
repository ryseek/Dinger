import Foundation
import GRDB

public nonisolated enum CardServiceError: Error, LocalizedError, Sendable {
    case noBackTerm
    case noFrontTerm
    case senseNotFound
    case duplicateAfterInvert
    case selectedTermNotFound

    public var errorDescription: String? {
        switch self {
        case .noBackTerm:            return "This sense has no translation on the target side."
        case .noFrontTerm:           return "This sense has no term on the front side."
        case .senseNotFound:         return "Sense not found."
        case .duplicateAfterInvert:  return "A card with the opposite direction already exists in this deck."
        case .selectedTermNotFound:  return "The selected translation is no longer available."
        }
    }
}

public nonisolated struct CardCreationResult: Sendable {
    public let card: Card
    public let isNew: Bool
    public let didUpdate: Bool
}

/// Deck + card + SRS management. All methods dispatch onto GRDB's writer queue.
public nonisolated final class CardService: @unchecked Sendable {

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Decks

    /// Returns (creating if missing) the default deck for a language pair.
    public func ensureDefaultDeck(for pair: LanguagePair) async throws -> Deck {
        try await database.dbWriter.write { db in
            let existing = try Deck.filter(Column("source_lang") == pair.source)
                .filter(Column("target_lang") == pair.target)
                .order(Column("id")).fetchOne(db)
            if let e = existing { return e }
            var deck = Deck(name: "\(pair.displayLabel) Deck",
                            sourceLang: pair.source,
                            targetLang: pair.target)
            try deck.insert(db)
            return deck
        }
    }

    public func allDecks() async throws -> [Deck] {
        try await database.dbWriter.read { db in
            try Deck.order(Column("created_at").asc).fetchAll(db)
        }
    }

    public func createDeck(name: String, pair: LanguagePair) async throws -> Deck {
        try await database.dbWriter.write { db in
            var deck = Deck(name: name, sourceLang: pair.source, targetLang: pair.target)
            try deck.insert(db)
            return deck
        }
    }

    public func deleteDeck(_ deck: Deck) async throws {
        guard let id = deck.id else { return }
        try await database.dbWriter.write { db in
            _ = try Deck.deleteOne(db, key: id)
        }
    }

    // MARK: - Cards

    /// Create a card from a SenseHit. Front = the user-facing prompt side
    /// chosen by `direction`; back = the selected term on the opposite side.
    public func createCard(from hit: SenseHit,
                           direction: CardDirection,
                           deck: Deck,
                           selectedSourceTermId: Int64? = nil,
                           selectedTargetTermId: Int64? = nil) async throws -> CardCreationResult {
        guard let deckId = deck.id else { throw CardServiceError.senseNotFound }

        let (front, back) = try Self.pickFrontBack(
            hit: hit,
            direction: direction,
            selectedSourceTermId: selectedSourceTermId,
            selectedTargetTermId: selectedTargetTermId
        )

        return try await database.dbWriter.write { db in
            if let existing = try Card
                .filter(Column("deck_id") == deckId)
                .filter(Column("sense_id") == hit.senseId)
                .filter(Column("direction") == direction.rawValue)
                .fetchOne(db) {
                guard existing.frontTermId != front.termId || existing.backTermId != back.termId else {
                    return CardCreationResult(card: existing, isNew: false, didUpdate: false)
                }
                try db.execute(sql: """
                    UPDATE card SET front_term_id = ?, back_term_id = ?
                     WHERE id = ?
                    """, arguments: [front.termId, back.termId, existing.id])
                var updated = existing
                updated.frontTermId = front.termId
                updated.backTermId = back.termId
                return CardCreationResult(card: updated, isNew: false, didUpdate: true)
            }

            var card = Card(
                deckId: deckId,
                senseId: hit.senseId,
                frontTermId: front.termId,
                backTermId: back.termId,
                direction: direction
            )
            try card.insert(db)

            let srs = CardSRS(cardId: card.id!)
            try srs.insert(db)

            return CardCreationResult(card: card, isNew: true, didUpdate: false)
        }
    }

    private static func pickFrontBack(hit: SenseHit,
                                      direction: CardDirection,
                                      selectedSourceTermId: Int64?,
                                      selectedTargetTermId: Int64?) throws -> (TermDisplay, TermDisplay) {
        let source = try pickTerm(
            from: hit.sourceTerms,
            selectedTermId: selectedSourceTermId,
            missingError: .noFrontTerm
        )
        let target = try pickTerm(
            from: hit.targetTerms,
            selectedTermId: selectedTargetTermId,
            missingError: .noBackTerm
        )
        switch direction {
        case .sourceToTarget:
            return (source, target)
        case .targetToSource:
            return (target, source)
        }
    }

    private static func pickTerm(from terms: [TermDisplay],
                                 selectedTermId: Int64?,
                                 missingError: CardServiceError) throws -> TermDisplay {
        guard !terms.isEmpty else { throw missingError }
        guard let selectedTermId else { return terms[0] }
        guard let term = terms.first(where: { $0.termId == selectedTermId }) else {
            throw CardServiceError.selectedTermNotFound
        }
        return term
    }

    public func cards(in deck: Deck) async throws -> [Card] {
        guard let deckId = deck.id else { return [] }
        return try await database.dbWriter.read { db in
            try Card.filter(Column("deck_id") == deckId)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    public func suspend(card: Card, _ value: Bool) async throws {
        guard let id = card.id else { return }
        try await database.dbWriter.write { db in
            try db.execute(sql: "UPDATE card SET suspended = ? WHERE id = ?",
                           arguments: [value, id])
        }
    }

    public func delete(card: Card) async throws {
        guard let id = card.id else { return }
        try await database.dbWriter.write { db in
            _ = try Card.deleteOne(db, key: id)
        }
    }

    /// Flip a card's direction in place: swap front/back term IDs and toggle
    /// direction. SRS state is preserved (we're still reviewing the same sense).
    /// Fails with `.duplicateAfterInvert` if a card with the opposite direction
    /// already exists for this deck+sense.
    @discardableResult
    public func invert(card: Card) async throws -> Card {
        guard let cardId = card.id else { return card }
        let newDirection: CardDirection = (card.direction == .sourceToTarget) ? .targetToSource : .sourceToTarget
        return try await database.dbWriter.write { db in
            let clash = try Card
                .filter(Column("deck_id") == card.deckId)
                .filter(Column("sense_id") == card.senseId)
                .filter(Column("direction") == newDirection.rawValue)
                .filter(Column("id") != cardId)
                .fetchOne(db)
            if clash != nil { throw CardServiceError.duplicateAfterInvert }

            try db.execute(sql: """
                UPDATE card SET front_term_id = ?, back_term_id = ?, direction = ?
                 WHERE id = ?
                """, arguments: [card.backTermId, card.frontTermId, newDirection.rawValue, cardId])

            var updated = card
            updated.frontTermId = card.backTermId
            updated.backTermId  = card.frontTermId
            updated.direction   = newDirection
            return updated
        }
    }

    // MARK: - SRS

    public func srs(for card: Card) async throws -> CardSRS? {
        guard let id = card.id else { return nil }
        return try await database.dbWriter.read { db in
            try CardSRS.filter(Column("card_id") == id).fetchOne(db)
        }
    }

    /// Apply a grade to a card: compute new SRS state, upsert it, and
    /// write a review_log row. Returns the new state.
    public func grade(card: Card, grade: Grade, now: Date = Date()) async throws -> CardSRS {
        guard let cardId = card.id else { throw CardServiceError.senseNotFound }
        return try await database.dbWriter.write { db in
            let existing = try CardSRS.filter(Column("card_id") == cardId).fetchOne(db)
                ?? CardSRS(cardId: cardId)
            let next = SM2Scheduler.update(srs: existing, grade: grade, now: now)
            try next.save(db)
            var log = SM2Scheduler.makeReviewLog(cardId: cardId, previous: existing, next: next, grade: grade, now: now)
            try log.insert(db)
            return next
        }
    }

    // MARK: - Queue for quiz

    /// Returns cards to review right now: due cards first (those that have
    /// actually been reviewed at least once and are past their interval),
    /// then new cards (never reviewed), capped at `maxNew` new cards.
    ///
    /// A freshly-created card has `due_at = now` and `last_reviewed_at = NULL`,
    /// which would otherwise make it match *both* buckets — "due" is therefore
    /// restricted to cards with a non-null `last_reviewed_at`.
    public func reviewQueue(deck: Deck, now: Date = Date(), maxCards: Int = 100, maxNew: Int = 20) async throws -> [Card] {
        guard let deckId = deck.id else { return [] }
        return try await database.dbWriter.read { db in
            let due = try Card.fetchAll(db, sql: """
                SELECT c.* FROM card c
                JOIN card_srs s ON s.card_id = c.id
                WHERE c.deck_id = ?
                  AND c.suspended = 0
                  AND s.last_reviewed_at IS NOT NULL
                  AND s.due_at <= ?
                ORDER BY s.due_at ASC
                LIMIT ?
                """, arguments: [deckId, now, maxCards])

            let remaining = max(0, maxCards - due.count)
            if remaining == 0 { return due }
            let newCap = min(remaining, maxNew)
            let newCards = try Card.fetchAll(db, sql: """
                SELECT c.* FROM card c
                LEFT JOIN card_srs s ON s.card_id = c.id
                WHERE c.deck_id = ?
                  AND c.suspended = 0
                  AND (s.card_id IS NULL OR s.last_reviewed_at IS NULL)
                ORDER BY c.created_at DESC
                LIMIT ?
                """, arguments: [deckId, newCap])

            return due + newCards
        }
    }

    /// Practice mode: every non-suspended card in the deck, prioritized by
    /// "most overdue first" so genuinely-due cards still come up first and
    /// already-known cards fill the tail. Grading still writes SRS as usual.
    public func practiceQueue(deck: Deck, maxCards: Int = 100) async throws -> [Card] {
        guard let deckId = deck.id else { return [] }
        return try await database.dbWriter.read { db in
            try Card.fetchAll(db, sql: """
                SELECT c.* FROM card c
                LEFT JOIN card_srs s ON s.card_id = c.id
                WHERE c.deck_id = ? AND c.suspended = 0
                ORDER BY
                    CASE WHEN s.last_reviewed_at IS NULL THEN 0 ELSE 1 END ASC,
                    COALESCE(s.due_at, c.created_at) ASC
                LIMIT ?
                """, arguments: [deckId, maxCards])
        }
    }
}
