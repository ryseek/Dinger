import Foundation
import GRDB

public nonisolated struct DictionarySearchHistoryItem: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var query: String
    public var direction: LookupDirection
    public var sourceLang: String
    public var targetLang: String
    public var searchedAt: Date

    public static let databaseTableName = "dictionary_search_history"

    enum CodingKeys: String, CodingKey {
        case id
        case query
        case direction
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
        case searchedAt = "searched_at"
    }

    public init(id: Int64? = nil,
                query: String,
                direction: LookupDirection,
                sourceLang: String,
                targetLang: String,
                searchedAt: Date = Date()) {
        self.id = id
        self.query = query
        self.direction = direction
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.searchedAt = searchedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public nonisolated struct DictionaryOpenedSenseHistoryItem: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var senseId: Int64
    public var matchedTermId: Int64
    public var sourceLang: String
    public var targetLang: String
    public var openedAt: Date

    public static let databaseTableName = "dictionary_opened_sense_history"

    enum CodingKeys: String, CodingKey {
        case id
        case senseId = "sense_id"
        case matchedTermId = "matched_term_id"
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
        case openedAt = "opened_at"
    }

    public init(id: Int64? = nil,
                senseId: Int64,
                matchedTermId: Int64,
                sourceLang: String,
                targetLang: String,
                openedAt: Date = Date()) {
        self.id = id
        self.senseId = senseId
        self.matchedTermId = matchedTermId
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.openedAt = openedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Persists dictionary searches and opened entries so users can return later
/// and save cards they skipped the first time.
public nonisolated final class DictionaryHistoryService: @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func recordSearch(query: String, direction: LookupDirection, pair: LanguagePair, now: Date = Date()) async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await database.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO dictionary_search_history (query, direction, source_lang, target_lang, searched_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(query, direction, source_lang, target_lang) DO UPDATE SET
                    searched_at = excluded.searched_at
                """, arguments: [trimmed, direction.rawValue, pair.source, pair.target, now])
        }
    }

    public func recordOpenedSense(hit: SenseHit, pair: LanguagePair, now: Date = Date()) async throws {
        try await database.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO dictionary_opened_sense_history (sense_id, matched_term_id, source_lang, target_lang, opened_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(sense_id, source_lang, target_lang) DO UPDATE SET
                    matched_term_id = excluded.matched_term_id,
                    opened_at = excluded.opened_at
                """, arguments: [hit.senseId, hit.matchedTermId, pair.source, pair.target, now])
        }
    }

    public func recentSearches(pair: LanguagePair, limit: Int = 20) async throws -> [DictionarySearchHistoryItem] {
        try await database.dbWriter.read { db in
            try DictionarySearchHistoryItem
                .filter(Column("source_lang") == pair.source)
                .filter(Column("target_lang") == pair.target)
                .order(Column("searched_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func recentOpenedSenses(pair: LanguagePair, limit: Int = 20) async throws -> [DictionaryOpenedSenseHistoryItem] {
        try await database.dbWriter.read { db in
            try DictionaryOpenedSenseHistoryItem
                .filter(Column("source_lang") == pair.source)
                .filter(Column("target_lang") == pair.target)
                .order(Column("opened_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
