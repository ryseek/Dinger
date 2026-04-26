import Foundation
import GRDB

public nonisolated enum CardServiceError: Error, LocalizedError, Sendable {
    case noBackTerm
    case noFrontTerm
    case senseNotFound
    case duplicateAfterInvert
    case selectedTermNotFound
    case invalidDeckName
    case invalidDeckFile
    case unsupportedDeckFileFormat(String)
    case unresolvedDeckCard(String)

    public var errorDescription: String? {
        switch self {
        case .noBackTerm:            return "This sense has no translation on the target side."
        case .noFrontTerm:           return "This sense has no term on the front side."
        case .senseNotFound:         return "Sense not found."
        case .duplicateAfterInvert:  return "A card with the opposite direction already exists in this deck."
        case .selectedTermNotFound:  return "The selected translation is no longer available."
        case .invalidDeckName:       return "Deck name can't be empty."
        case .invalidDeckFile:       return "This deck file is malformed or incomplete."
        case .unsupportedDeckFileFormat(let format):
            return "Unsupported deck file format: \(format)."
        case .unresolvedDeckCard(let detail):
            return "This deck contains a card that can't be matched to the current dictionary: \(detail)."
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

    public func renameDeck(_ deck: Deck, to name: String) async throws -> Deck {
        guard let id = deck.id else { throw CardServiceError.invalidDeckName }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CardServiceError.invalidDeckName }

        return try await database.dbWriter.write { db in
            try db.execute(sql: "UPDATE deck SET name = ? WHERE id = ?",
                           arguments: [trimmed, id])
            var updated = deck
            updated.name = trimmed
            return updated
        }
    }

    public func deleteDeck(_ deck: Deck) async throws {
        guard let id = deck.id else { return }
        try await database.dbWriter.write { db in
            _ = try Deck.deleteOne(db, key: id)
        }
    }

    public func exportDeck(_ deck: Deck) async throws -> Data {
        guard let deckId = deck.id else { throw CardServiceError.invalidDeckFile }
        let export = try await database.dbWriter.read { db in
            let cards = try Card.filter(Column("deck_id") == deckId)
                .order(Column("created_at").asc)
                .fetchAll(db)
            let exportedCards = try cards.map { try Self.exportedCard(db: db, deck: deck, card: $0) }
            return DeckExportFile(
                deck: ExportedDeck(
                    name: deck.name,
                    sourceLang: deck.sourceLang,
                    targetLang: deck.targetLang
                ),
                cards: exportedCards
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    public func importDeck(from data: Data, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Deck {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let export: DeckExportFile
        do {
            export = try decoder.decode(DeckExportFile.self, from: data)
        } catch {
            throw CardServiceError.invalidDeckFile
        }

        guard export.format == DeckExportFormat.current else {
            throw CardServiceError.unsupportedDeckFileFormat(export.format)
        }

        let deckName = export.deck.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deckName.isEmpty else { throw CardServiceError.invalidDeckName }
        guard !export.deck.sourceLang.isEmpty, !export.deck.targetLang.isEmpty else {
            throw CardServiceError.invalidDeckFile
        }
        progress?(0)

        return try await database.dbWriter.write { db in
            guard try Self.hasDictionary(db: db, sourceLang: export.deck.sourceLang, targetLang: export.deck.targetLang) else {
                throw CardServiceError.unresolvedDeckCard("\(export.deck.sourceLang)-\(export.deck.targetLang)")
            }

            var deck = Deck(
                name: deckName,
                sourceLang: export.deck.sourceLang,
                targetLang: export.deck.targetLang
            )
            try deck.insert(db)
            guard let deckId = deck.id else { throw CardServiceError.invalidDeckFile }

            let totalCards = export.cards.count
            if totalCards == 0 {
                progress?(1)
            }

            for (index, exportedCard) in export.cards.enumerated() {
                let senseId = try Self.resolveSenseId(db: db, key: exportedCard.senseKey)
                let frontTermIds = try Self.resolveTermIds(
                    db: db,
                    terms: exportedCard.frontTerms,
                    senseId: senseId
                )
                let backTermIds = try Self.resolveTermIds(
                    db: db,
                    terms: exportedCard.backTerms,
                    senseId: senseId
                )
                guard let frontTermId = frontTermIds.first,
                      let backTermId = backTermIds.first else {
                    throw CardServiceError.invalidDeckFile
                }

                var card = Card(
                    deckId: deckId,
                    senseId: senseId,
                    frontTermId: frontTermId,
                    backTermId: backTermId,
                    frontTermIds: frontTermIds,
                    backTermIds: backTermIds,
                    direction: exportedCard.direction,
                    createdAt: exportedCard.createdAt,
                    suspended: exportedCard.suspended
                )
                try card.insert(db)
                try CardSRS(cardId: card.id!).insert(db)
                progress?(Double(index + 1) / Double(totalCards))
            }

            return deck
        }
    }

    // MARK: - Cards

    /// Create a card from a SenseHit. Front = the user-facing prompt side
    /// chosen by `direction`; back = the selected term on the opposite side.
    public func createCard(from hit: SenseHit,
                           direction: CardDirection,
                           deck: Deck,
                           selectedSourceTermId: Int64? = nil,
                           selectedTargetTermId: Int64? = nil,
                           selectedSourceTermIds: [Int64]? = nil,
                           selectedTargetTermIds: [Int64]? = nil) async throws -> CardCreationResult {
        guard let deckId = deck.id else { throw CardServiceError.senseNotFound }

        let (front, back) = try Self.pickFrontBack(
            hit: hit,
            direction: direction,
            selectedSourceTermIds: selectedSourceTermIds ?? selectedSourceTermId.map { [$0] },
            selectedTargetTermIds: selectedTargetTermIds ?? selectedTargetTermId.map { [$0] }
        )

        return try await database.dbWriter.write { db in
            if let existing = try Card
                .filter(Column("deck_id") == deckId)
                .filter(Column("sense_id") == hit.senseId)
                .filter(Column("direction") == direction.rawValue)
                .fetchOne(db) {
                let frontIdsRaw = Card.encodeTermIds(front.map(\.termId))
                let backIdsRaw = Card.encodeTermIds(back.map(\.termId))
                guard existing.frontTermId != front[0].termId ||
                        existing.backTermId != back[0].termId ||
                        existing.frontTermIdsRaw != frontIdsRaw ||
                        existing.backTermIdsRaw != backIdsRaw else {
                    return CardCreationResult(card: existing, isNew: false, didUpdate: false)
                }
                try db.execute(sql: """
                    UPDATE card
                       SET front_term_id = ?,
                           back_term_id = ?,
                           front_term_ids = ?,
                           back_term_ids = ?
                     WHERE id = ?
                    """, arguments: [front[0].termId, back[0].termId, frontIdsRaw, backIdsRaw, existing.id])
                var updated = existing
                updated.frontTermId = front[0].termId
                updated.backTermId = back[0].termId
                updated.frontTermIdsRaw = frontIdsRaw
                updated.backTermIdsRaw = backIdsRaw
                return CardCreationResult(card: updated, isNew: false, didUpdate: true)
            }

            var card = Card(
                deckId: deckId,
                senseId: hit.senseId,
                frontTermId: front[0].termId,
                backTermId: back[0].termId,
                frontTermIds: front.map(\.termId),
                backTermIds: back.map(\.termId),
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
                                      selectedSourceTermIds: [Int64]?,
                                      selectedTargetTermIds: [Int64]?) throws -> ([TermDisplay], [TermDisplay]) {
        let source = try pickTerm(
            from: hit.sourceTerms,
            selectedTermIds: selectedSourceTermIds,
            missingError: .noFrontTerm
        )
        let target = try pickTerm(
            from: hit.targetTerms,
            selectedTermIds: selectedTargetTermIds,
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
                                 selectedTermIds: [Int64]?,
                                 missingError: CardServiceError) throws -> [TermDisplay] {
        guard !terms.isEmpty else { throw missingError }
        guard let selectedTermIds, !selectedTermIds.isEmpty else { return [terms[0]] }
        let selected = terms.filter { selectedTermIds.contains($0.termId) }
        guard selected.count == Set(selectedTermIds).count else {
            throw CardServiceError.selectedTermNotFound
        }
        return selected
    }

    private nonisolated static func exportedCard(db: Database, deck: Deck, card: Card) throws -> ExportedCard {
        guard let senseRow = try Row.fetchOne(db, sql: """
            SELECT e.raw AS entry_raw, s.position AS sense_position
              FROM sense s
              JOIN entry e ON e.id = s.entry_id
             WHERE s.id = ?
            """, arguments: [card.senseId]) else {
            throw CardServiceError.senseNotFound
        }

        let senseKey = ExportedSenseKey(
            sourceLang: deck.sourceLang,
            targetLang: deck.targetLang,
            entryRaw: senseRow["entry_raw"],
            sensePosition: senseRow["sense_position"]
        )

        return ExportedCard(
            senseKey: senseKey,
            direction: card.direction,
            frontTerms: try exportedTerms(db: db, senseId: card.senseId, termIds: card.frontTermIds),
            backTerms: try exportedTerms(db: db, senseId: card.senseId, termIds: card.backTermIds),
            suspended: card.suspended,
            createdAt: card.createdAt
        )
    }

    private nonisolated static func exportedTerms(db: Database, senseId: Int64, termIds: [Int64]) throws -> [ExportedTerm] {
        try termIds.map { termId in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT l.code AS language,
                       t.surface,
                       t.headword,
                       t.normalized,
                       t.pos,
                       t.gender
                  FROM term t
                  JOIN language l ON l.id = t.language_id
                 WHERE t.id = ? AND t.sense_id = ?
                """, arguments: [termId, senseId]) else {
                throw CardServiceError.selectedTermNotFound
            }

            return ExportedTerm(
                language: row["language"],
                surface: row["surface"],
                headword: row["headword"],
                normalized: row["normalized"],
                pos: row["pos"],
                gender: row["gender"]
            )
        }
    }

    private nonisolated static func hasDictionary(db: Database, sourceLang: String, targetLang: String) throws -> Bool {
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
              FROM dictionary d
              JOIN language sl ON sl.id = d.source_lang_id
              JOIN language tl ON tl.id = d.target_lang_id
             WHERE sl.code = ? AND tl.code = ?
            """, arguments: [sourceLang, targetLang]) ?? 0
        return count > 0
    }

    private nonisolated static func resolveSenseId(db: Database, key: ExportedSenseKey) throws -> Int64 {
        let ids = try Int64.fetchAll(db, sql: """
            SELECT s.id
              FROM sense s
              JOIN entry e ON e.id = s.entry_id
              JOIN dictionary d ON d.id = e.dictionary_id
              JOIN language sl ON sl.id = d.source_lang_id
              JOIN language tl ON tl.id = d.target_lang_id
             WHERE sl.code = ?
               AND tl.code = ?
               AND e.raw = ?
               AND s.position = ?
            """, arguments: [key.sourceLang, key.targetLang, key.entryRaw, key.sensePosition])

        guard ids.count == 1, let senseId = ids.first else {
            throw CardServiceError.unresolvedDeckCard(key.entryRaw)
        }
        return senseId
    }

    private nonisolated static func resolveTermIds(db: Database, terms: [ExportedTerm], senseId: Int64) throws -> [Int64] {
        try terms.map { term in
            let ids = try Int64.fetchAll(db, sql: """
                SELECT t.id
                  FROM term t
                  JOIN language l ON l.id = t.language_id
                 WHERE t.sense_id = ?
                   AND l.code = ?
                   AND t.surface = ?
                   AND t.headword = ?
                   AND t.normalized = ?
                   AND (t.pos IS ? OR t.pos = ?)
                   AND (t.gender IS ? OR t.gender = ?)
                """, arguments: [
                    senseId,
                    term.language,
                    term.surface,
                    term.headword,
                    term.normalized,
                    term.pos,
                    term.pos,
                    term.gender,
                    term.gender
                ])

            guard ids.count == 1, let termId = ids.first else {
                throw CardServiceError.unresolvedDeckCard(term.surface)
            }
            return termId
        }
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
                UPDATE card
                   SET front_term_id = ?,
                       back_term_id = ?,
                       front_term_ids = ?,
                       back_term_ids = ?,
                       direction = ?
                 WHERE id = ?
                """, arguments: [
                    card.backTermId,
                    card.frontTermId,
                    card.backTermIdsRaw,
                    card.frontTermIdsRaw,
                    newDirection.rawValue,
                    cardId
                ])

            var updated = card
            updated.frontTermId = card.backTermId
            updated.backTermId  = card.frontTermId
            updated.frontTermIdsRaw = card.backTermIdsRaw
            updated.backTermIdsRaw = card.frontTermIdsRaw
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
