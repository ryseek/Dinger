import Foundation
import GRDB

/// One-time importer from the legacy monolithic `dinger.sqlite` into the
/// split, user-only schema. The source is never schema-migrated or deleted by
/// this type. Activation is handled by an atomic file rename in `AppDatabase`.
nonisolated enum LegacyDatabaseImporter {
    private struct SenseCacheKey: Hashable {
        var oldId: Int64
        var source: String
        var target: String
    }

    private struct TermCacheKey: Hashable {
        var oldId: Int64
        var newSenseId: Int64
    }

    static func importDatabase(from legacyURL: URL,
                               to destinationURL: URL,
                               dictionaryURL: URL) throws {
        try checkpointAndValidateLegacy(at: legacyURL)
        try UserDatabaseSchema.createFresh(at: destinationURL)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(
                sql: "ATTACH DATABASE ? AS dict",
                arguments: [AppDatabase.readOnlySQLiteURI(for: dictionaryURL, immutable: true)]
            )
            try db.execute(
                sql: "ATTACH DATABASE ? AS legacy",
                arguments: [AppDatabase.readOnlySQLiteURI(for: legacyURL, immutable: false)]
            )
        }

        let queue = try DatabaseQueue(path: destinationURL.path, configuration: configuration)
        try queue.write { db in
            guard try tableExists("deck", in: "legacy", db: db),
                  try tableExists("card", in: "legacy", db: db) else {
                throw AppDatabaseError.invalidLegacyDatabase("Deck or card table is missing.")
            }

            var senseCache: [SenseCacheKey: Int64] = [:]
            var termCache: [TermCacheKey: Int64] = [:]

            try copyDecks(db: db)
            try copyCards(
                db: db,
                senseCache: &senseCache,
                termCache: &termCache
            )
            try copySRS(db: db)
            try copyReviewLog(db: db)
            try copySearchHistory(db: db)
            try copyOpenedHistory(
                db: db,
                senseCache: &senseCache,
                termCache: &termCache
            )

            try validateCopiedCounts(db: db)
            let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA main.foreign_key_check")
            guard foreignKeyFailures.isEmpty else {
                throw AppDatabaseError.invalidLegacyDatabase(
                    "Imported user data failed foreign-key validation."
                )
            }

            try setMetadata("legacy_migration_complete", value: "1", db: db)
            try setMetadata("legacy_cleanup_pending", value: "1", db: db)
            try setMetadata("legacy_activation_confirmed", value: "0", db: db)
            try setMetadata(
                "legacy_migrated_at",
                value: ISO8601DateFormatter().string(from: Date()),
                db: db
            )
        }

        try queue.read { db in
            try UserDatabaseSchema.validate(db)
        }
        try queue.close()
    }

    // MARK: - Source preparation

    private static func checkpointAndValidateLegacy(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.writeWithoutTransaction { db in
            let result = try String.fetchOne(db, sql: "PRAGMA main.quick_check")
            guard result == "ok" else {
                throw AppDatabaseError.invalidLegacyDatabase(result ?? "quick_check failed")
            }
            // The old app used a pool and may have left the newest reviews in
            // WAL. Checkpoint before reopening the source read-only.
            _ = try Row.fetchAll(db, sql: "PRAGMA wal_checkpoint(FULL)")
        }
        try queue.close()
    }

    // MARK: - User tables

    private static func copyDecks(db: Database) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, name, source_lang, target_lang, created_at
              FROM legacy.deck
             ORDER BY id
            """)
        for row in rows {
            var deck = Deck(
                id: row["id"],
                name: row["name"],
                sourceLang: row["source_lang"],
                targetLang: row["target_lang"],
                createdAt: row["created_at"]
            )
            try deck.insert(db)
        }
    }

    private static func copyCards(db: Database,
                                  senseCache: inout [SenseCacheKey: Int64],
                                  termCache: inout [TermCacheKey: Int64]) throws {
        let columns = try columnNames(table: "card", schema: "legacy", db: db)
        let frontIDs = columns.contains("front_term_ids")
            ? "front_term_ids"
            : "CAST(front_term_id AS TEXT)"
        let backIDs = columns.contains("back_term_ids")
            ? "back_term_ids"
            : "CAST(back_term_id AS TEXT)"
        let frontOverride = columns.contains("front_text_override")
            ? "front_text_override"
            : "NULL"
        let backOverride = columns.contains("back_text_override")
            ? "back_text_override"
            : "NULL"

        let rows = try Row.fetchAll(db, sql: """
            SELECT c.id,
                   c.deck_id,
                   c.sense_id,
                   c.front_term_id,
                   c.back_term_id,
                   c.direction,
                   c.created_at,
                   c.suspended,
                   \(frontIDs) AS front_term_ids,
                   \(backIDs) AS back_term_ids,
                   \(frontOverride) AS front_text_override,
                   \(backOverride) AS back_text_override,
                   d.source_lang,
                   d.target_lang
              FROM legacy.card c
              JOIN legacy.deck d ON d.id = c.deck_id
             ORDER BY c.id
            """)

        for row in rows {
            let source: String = row["source_lang"]
            let target: String = row["target_lang"]
            let oldSenseId: Int64 = row["sense_id"]
            let newSenseId = try resolveSense(
                oldId: oldSenseId,
                source: source,
                target: target,
                db: db,
                cache: &senseCache
            )

            let oldFrontId: Int64 = row["front_term_id"]
            let oldBackId: Int64 = row["back_term_id"]
            let newFrontId = try resolveTerm(
                oldId: oldFrontId,
                newSenseId: newSenseId,
                db: db,
                cache: &termCache
            )
            let newBackId = try resolveTerm(
                oldId: oldBackId,
                newSenseId: newSenseId,
                db: db,
                cache: &termCache
            )

            let rawFrontIDs: String = row["front_term_ids"]
            let rawBackIDs: String = row["back_term_ids"]
            let oldFrontIDs = nonEmptyTermIDs(rawFrontIDs, fallback: oldFrontId)
            let oldBackIDs = nonEmptyTermIDs(rawBackIDs, fallback: oldBackId)
            let newFrontIDs = try oldFrontIDs.map {
                try resolveTerm(
                    oldId: $0,
                    newSenseId: newSenseId,
                    db: db,
                    cache: &termCache
                )
            }
            let newBackIDs = try oldBackIDs.map {
                try resolveTerm(
                    oldId: $0,
                    newSenseId: newSenseId,
                    db: db,
                    cache: &termCache
                )
            }

            let directionRaw: String = row["direction"]
            guard let direction = CardDirection(rawValue: directionRaw) else {
                throw AppDatabaseError.invalidLegacyDatabase(
                    "Card \(row["id"] as Int64) has an invalid direction."
                )
            }
            let suspendedValue: Int = row["suspended"]
            var card = Card(
                id: row["id"],
                deckId: row["deck_id"],
                senseId: newSenseId,
                frontTermId: newFrontId,
                backTermId: newBackId,
                frontTermIds: newFrontIDs,
                backTermIds: newBackIDs,
                frontTextOverride: row["front_text_override"],
                backTextOverride: row["back_text_override"],
                direction: direction,
                createdAt: row["created_at"],
                suspended: suspendedValue != 0
            )
            try card.insert(db)
            guard let cardId = card.id else {
                throw AppDatabaseError.invalidLegacyDatabase("A card lost its primary key.")
            }
            try CardDictionaryReferenceStore.refresh(cardId: cardId, db: db)
        }
    }

    private static func copySRS(db: Database) throws {
        guard try tableExists("card_srs", in: "legacy", db: db) else { return }
        let rows = try Row.fetchAll(db, sql: """
            SELECT card_id, ease, interval_days, repetitions, lapses,
                   due_at, last_reviewed_at
              FROM legacy.card_srs
             ORDER BY card_id
            """)
        for row in rows {
            try CardSRS(
                cardId: row["card_id"],
                ease: row["ease"],
                intervalDays: row["interval_days"],
                repetitions: row["repetitions"],
                lapses: row["lapses"],
                dueAt: row["due_at"],
                lastReviewedAt: row["last_reviewed_at"]
            ).insert(db)
        }
    }

    private static func copyReviewLog(db: Database) throws {
        guard try tableExists("review_log", in: "legacy", db: db) else { return }
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, card_id, reviewed_at, grade, prev_interval,
                   new_interval, prev_ease, new_ease
              FROM legacy.review_log
             ORDER BY id
            """)
        for row in rows {
            var review = ReviewLog(
                id: row["id"],
                cardId: row["card_id"],
                reviewedAt: row["reviewed_at"],
                grade: row["grade"],
                prevInterval: row["prev_interval"],
                newInterval: row["new_interval"],
                prevEase: row["prev_ease"],
                newEase: row["new_ease"]
            )
            try review.insert(db)
        }
    }

    private static func copySearchHistory(db: Database) throws {
        guard try tableExists("dictionary_search_history", in: "legacy", db: db) else { return }
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, query, direction, source_lang, target_lang, searched_at
              FROM legacy.dictionary_search_history
             ORDER BY id
            """)
        for row in rows {
            let directionRaw: String = row["direction"]
            guard let direction = LookupDirection(rawValue: directionRaw) else {
                throw AppDatabaseError.invalidLegacyDatabase(
                    "Search history contains an invalid direction."
                )
            }
            var item = DictionarySearchHistoryItem(
                id: row["id"],
                query: row["query"],
                direction: direction,
                sourceLang: row["source_lang"],
                targetLang: row["target_lang"],
                searchedAt: row["searched_at"]
            )
            try item.insert(db)
        }
    }

    private static func copyOpenedHistory(db: Database,
                                          senseCache: inout [SenseCacheKey: Int64],
                                          termCache: inout [TermCacheKey: Int64]) throws {
        guard try tableExists("dictionary_opened_sense_history", in: "legacy", db: db) else { return }
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, sense_id, matched_term_id, source_lang, target_lang, opened_at
              FROM legacy.dictionary_opened_sense_history
             ORDER BY id
            """)
        for row in rows {
            let newSenseId = try resolveSense(
                oldId: row["sense_id"],
                source: row["source_lang"],
                target: row["target_lang"],
                db: db,
                cache: &senseCache
            )
            let newTermId = try resolveTerm(
                oldId: row["matched_term_id"],
                newSenseId: newSenseId,
                db: db,
                cache: &termCache
            )
            var item = DictionaryOpenedSenseHistoryItem(
                id: row["id"],
                senseId: newSenseId,
                matchedTermId: newTermId,
                sourceLang: row["source_lang"],
                targetLang: row["target_lang"],
                openedAt: row["opened_at"]
            )
            try item.insert(db)
        }
    }

    // MARK: - Semantic remapping

    private static func resolveSense(oldId: Int64,
                                     source: String,
                                     target: String,
                                     db: Database,
                                     cache: inout [SenseCacheKey: Int64]) throws -> Int64 {
        let cacheKey = SenseCacheKey(oldId: oldId, source: source, target: target)
        if let cached = cache[cacheKey] { return cached }

        guard let legacySense = try Row.fetchOne(db, sql: """
            SELECT e.raw, s.position
              FROM legacy.sense s
              JOIN legacy.entry e ON e.id = s.entry_id
             WHERE s.id = ?
            """, arguments: [oldId]) else {
            throw AppDatabaseError.unresolvedDictionaryReference("sense \(oldId)")
        }

        // Normal upgrades keep the same bundled dictionary IDs. Verify that
        // cheap primary-key path semantically before falling back to the
        // stable export identity for a rebuilt/reordered seed.
        if let sameID = try Row.fetchOne(db, sql: """
            SELECT e.raw, s.position, sl.code AS source_lang, tl.code AS target_lang
              FROM dict.sense s
              JOIN dict.entry e ON e.id = s.entry_id
              JOIN dict.dictionary d ON d.id = e.dictionary_id
              JOIN dict.language sl ON sl.id = d.source_lang_id
              JOIN dict.language tl ON tl.id = d.target_lang_id
             WHERE s.id = ?
            """, arguments: [oldId]),
           sameID["raw"] as String == legacySense["raw"] as String,
           sameID["position"] as Int == legacySense["position"] as Int,
           sameID["source_lang"] as String == source,
           sameID["target_lang"] as String == target {
            cache[cacheKey] = oldId
            return oldId
        }

        let ids = try Int64.fetchAll(db, sql: """
            SELECT s.id
              FROM dict.sense s
              JOIN dict.entry e ON e.id = s.entry_id
              JOIN dict.dictionary d ON d.id = e.dictionary_id
              JOIN dict.language sl ON sl.id = d.source_lang_id
              JOIN dict.language tl ON tl.id = d.target_lang_id
             WHERE sl.code = ?
               AND tl.code = ?
               AND e.raw = ?
               AND s.position = ?
            """, arguments: [
                source,
                target,
                legacySense["raw"] as String,
                legacySense["position"] as Int,
            ])
        guard ids.count == 1, let resolved = ids.first else {
            let raw: String = legacySense["raw"]
            throw AppDatabaseError.unresolvedDictionaryReference(raw)
        }
        cache[cacheKey] = resolved
        return resolved
    }

    private static func resolveTerm(oldId: Int64,
                                    newSenseId: Int64,
                                    db: Database,
                                    cache: inout [TermCacheKey: Int64]) throws -> Int64 {
        let cacheKey = TermCacheKey(oldId: oldId, newSenseId: newSenseId)
        if let cached = cache[cacheKey] { return cached }

        guard let oldTerm = try Row.fetchOne(db, sql: """
            SELECT l.code AS language,
                   t.surface,
                   t.headword,
                   t.normalized,
                   t.pos,
                   t.gender
              FROM legacy.term t
              JOIN legacy.language l ON l.id = t.language_id
             WHERE t.id = ?
            """, arguments: [oldId]) else {
            throw AppDatabaseError.unresolvedDictionaryReference("term \(oldId)")
        }

        let pos: String? = oldTerm["pos"]
        let gender: String? = oldTerm["gender"]
        if let sameID = try Row.fetchOne(db, sql: """
            SELECT l.code AS language,
                   t.sense_id,
                   t.surface,
                   t.headword,
                   t.normalized,
                   t.pos,
                   t.gender
              FROM dict.term t
              JOIN dict.language l ON l.id = t.language_id
             WHERE t.id = ?
            """, arguments: [oldId]),
           sameID["sense_id"] as Int64 == newSenseId,
           sameID["language"] as String == oldTerm["language"] as String,
           sameID["surface"] as String == oldTerm["surface"] as String,
           sameID["headword"] as String == oldTerm["headword"] as String,
           sameID["normalized"] as String == oldTerm["normalized"] as String,
           sameID["pos"] as String? == pos,
           sameID["gender"] as String? == gender {
            cache[cacheKey] = oldId
            return oldId
        }

        let ids = try Int64.fetchAll(db, sql: """
            SELECT t.id
              FROM dict.term t
              JOIN dict.language l ON l.id = t.language_id
             WHERE t.sense_id = ?
               AND l.code = ?
               AND t.surface = ?
               AND t.headword = ?
               AND t.normalized = ?
               AND (t.pos IS ? OR t.pos = ?)
               AND (t.gender IS ? OR t.gender = ?)
            """, arguments: [
                newSenseId,
                oldTerm["language"] as String,
                oldTerm["surface"] as String,
                oldTerm["headword"] as String,
                oldTerm["normalized"] as String,
                pos,
                pos,
                gender,
                gender,
            ])
        guard ids.count == 1, let resolved = ids.first else {
            let surface: String = oldTerm["surface"]
            throw AppDatabaseError.unresolvedDictionaryReference(surface)
        }
        cache[cacheKey] = resolved
        return resolved
    }

    // MARK: - Validation and metadata

    private static func validateCopiedCounts(db: Database) throws {
        let tables = [
            "deck",
            "card",
            "card_srs",
            "review_log",
            "dictionary_search_history",
            "dictionary_opened_sense_history",
        ]
        for table in tables {
            let sourceCount: Int
            if try tableExists(table, in: "legacy", db: db) {
                sourceCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM legacy.\(table)"
                ) ?? 0
            } else {
                sourceCount = 0
            }
            let destinationCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM main.\(table)"
            ) ?? 0
            guard sourceCount == destinationCount else {
                throw AppDatabaseError.invalidLegacyDatabase(
                    "\(table) count changed from \(sourceCount) to \(destinationCount)."
                )
            }
        }

        let cardCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM main.card") ?? 0
        let referenceCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM main.card_dictionary_reference"
        ) ?? 0
        guard cardCount == referenceCount else {
            throw AppDatabaseError.invalidLegacyDatabase(
                "Not every card received a durable dictionary reference."
            )
        }
    }

    private static func tableExists(_ table: String,
                                    in schema: String,
                                    db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: """
            SELECT 1
              FROM \(schema).sqlite_master
             WHERE type = 'table' AND name = ?
            """, arguments: [table]) != nil
    }

    private static func columnNames(table: String,
                                    schema: String,
                                    db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: "PRAGMA \(schema).table_info('\(table)')")
        return Set(rows.map { $0["name"] as String })
    }

    private static func nonEmptyTermIDs(_ raw: String, fallback: Int64) -> [Int64] {
        let ids = Card.decodeTermIds(raw)
        return ids.isEmpty ? [fallback] : ids
    }

    private static func setMetadata(_ key: String, value: String, db: Database) throws {
        try db.execute(sql: """
            INSERT INTO app_metadata (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, arguments: [key, value])
    }
}
