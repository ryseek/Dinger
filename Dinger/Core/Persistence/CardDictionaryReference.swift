import Foundation
import GRDB

/// A small, versioned semantic copy of a card's dictionary selection.
/// Numeric IDs in `card` are a cache; this payload is the durable identity.
nonisolated struct CardDictionaryReference: Codable, Hashable, Sendable {
    static let format = "dinger.card-dictionary-reference.v1"

    var senseKey: ExportedSenseKey
    var frontTerms: [ExportedTerm]
    var backTerms: [ExportedTerm]
}

nonisolated enum CardDictionaryReferenceStore {
    static func refresh(cardId: Int64, db: Database) throws {
        guard let card = try Card.fetchOne(db, key: cardId),
              let deck = try Deck.fetchOne(db, key: card.deckId) else {
            throw CardServiceError.senseNotFound
        }

        guard let sense = try Row.fetchOne(db, sql: """
            SELECT e.raw AS entry_raw, s.position AS sense_position
              FROM dict.sense s
              JOIN dict.entry e ON e.id = s.entry_id
             WHERE s.id = ?
            """, arguments: [card.senseId]) else {
            throw CardServiceError.senseNotFound
        }

        let reference = CardDictionaryReference(
            senseKey: ExportedSenseKey(
                sourceLang: deck.sourceLang,
                targetLang: deck.targetLang,
                entryRaw: sense["entry_raw"],
                sensePosition: sense["sense_position"]
            ),
            frontTerms: try terms(db: db, senseId: card.senseId, ids: card.frontTermIds),
            backTerms: try terms(db: db, senseId: card.senseId, ids: card.backTermIds)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(reference)
        try db.execute(sql: """
            INSERT INTO card_dictionary_reference (card_id, format, payload)
            VALUES (?, ?, ?)
            ON CONFLICT(card_id) DO UPDATE SET
                format = excluded.format,
                payload = excluded.payload
            """, arguments: [cardId, CardDictionaryReference.format, payload])
    }

    private static func terms(db: Database, senseId: Int64, ids: [Int64]) throws -> [ExportedTerm] {
        try ids.map { id in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT l.code AS language,
                       t.surface,
                       t.headword,
                       t.normalized,
                       t.pos,
                       t.gender
                  FROM dict.term t
                  JOIN dict.language l ON l.id = t.language_id
                 WHERE t.id = ? AND t.sense_id = ?
                """, arguments: [id, senseId]) else {
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
}
