import Foundation
import GRDB

public nonisolated final class ExampleSentenceService: @unchecked Sendable {
    private let reader: any DatabaseReader

    public init(reader: any DatabaseReader) {
        self.reader = reader
    }

    public convenience init(database: AppDatabase) {
        self.init(reader: database.dbWriter)
    }

    public func examples(for termId: Int64, limit: Int = 3) async throws -> [ExampleSentence] {
        try await reader.read { db in
            try Self.fetchExamples(db: db, termId: termId, limit: limit)
        }
    }

    public func bestExample(for card: Card, direction: CardDirection? = nil) async throws -> ExampleSentence? {
        let effectiveDirection = direction ?? card.direction
        let frontTermId = effectiveDirection == card.direction ? card.frontTermId : card.backTermId
        let matches = try await examples(for: frontTermId, limit: 1)
        return matches.first
    }

    static func fetchExamples(db: Database, termId: Int64, limit: Int) throws -> [ExampleSentence] {
        guard limit > 0,
              let term = try Row.fetchOne(db, sql: """
                  SELECT t.normalized, l.code AS language_code
                    FROM term t
                    JOIN language l ON l.id = t.language_id
                   WHERE t.id = ?
                  """, arguments: [termId]) else {
            return []
        }

        let normalized: String = term["normalized"]
        let languageCode: String = term["language_code"]
        let query = ftsColumnQuery(for: languageCode, normalized: normalized)
        guard !query.isEmpty else { return [] }

        let lengthExpression = languageCode == "de" ? "LENGTH(e.de_text)" : "LENGTH(e.en_text)"
        let duplicateExpression = languageCode == "de" ? "e.de_normalized" : "e.en_normalized"
        let rows = try Row.fetchAll(db, sql: """
            WITH ranked_examples AS (
            SELECT e.id,
                   e.de_tatoeba_id,
                   e.en_tatoeba_id,
                   e.de_text,
                   e.en_text,
                   f.rank AS match_rank,
                   \(lengthExpression) AS matched_length,
                   ROW_NUMBER() OVER (
                       PARTITION BY \(duplicateExpression)
                       ORDER BY f.rank, \(lengthExpression), e.id
                   ) AS duplicate_rank
              FROM example_sentence_fts f
              JOIN example_sentence e ON e.id = f.rowid
             WHERE example_sentence_fts MATCH ?
            )
            SELECT id,
                   de_tatoeba_id,
                   en_tatoeba_id,
                   de_text,
                   en_text
              FROM ranked_examples
             WHERE duplicate_rank = 1
             ORDER BY match_rank, matched_length, id
             LIMIT ?
            """, arguments: [query, limit])

        return rows.map { row in
            ExampleSentence(
                id: row["id"],
                germanTatoebaId: row["de_tatoeba_id"],
                englishTatoebaId: row["en_tatoeba_id"],
                germanText: row["de_text"],
                englishText: row["en_text"]
            )
        }
    }

    private static func ftsColumnQuery(for languageCode: String, normalized: String) -> String {
        let column: String
        switch languageCode {
        case "de": column = "de_normalized"
        case "en": column = "en_normalized"
        default: return ""
        }

        let escaped = normalized.replacingOccurrences(of: "\"", with: "\"\"")
        guard !escaped.isEmpty else { return "" }
        return "\(column): \"\(escaped)\""
    }
}
