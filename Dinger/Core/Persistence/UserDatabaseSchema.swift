import Foundation
import GRDB

/// The writable, user-owned half of the split database.
///
/// Fresh databases are created directly at `currentVersion`. Existing split
/// databases run only the incremental upgrades newer than their stored
/// `user_version`, so a fresh install never replays the historical chain.
nonisolated enum UserDatabaseSchema {
    static let currentVersion = 1

    static let requiredTables: Set<String> = [
        "app_metadata",
        "deck",
        "card",
        "card_dictionary_reference",
        "card_srs",
        "review_log",
        "dictionary_search_history",
        "dictionary_opened_sense_history",
    ]

    static func createFresh(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try createCurrent(in: db)
        }
        try queue.close()
    }

    static func version(in db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "PRAGMA main.user_version") ?? 0
    }

    static func prepareExisting(in db: Database) throws {
        let version = try version(in: db)
        guard version > 0 else {
            throw AppDatabaseError.invalidUserDatabase(
                "The user database has no split-schema version."
            )
        }
        guard version <= currentVersion else {
            throw AppDatabaseError.unsupportedUserDatabaseVersion(version)
        }

        if version < currentVersion {
            try db.inTransaction {
                // Add future upgrades here, guarded by `version < N`. Fresh
                // databases will already be created at the latest schema below.
                return .commit
            }
        }
    }

    static func createCurrent(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE app_metadata (
                key    TEXT PRIMARY KEY NOT NULL,
                value  TEXT NOT NULL
            );

            CREATE TABLE deck (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                name         TEXT NOT NULL,
                source_lang  TEXT NOT NULL,
                target_lang  TEXT NOT NULL,
                created_at   DATETIME NOT NULL
            );

            CREATE TABLE card (
                id                    INTEGER PRIMARY KEY AUTOINCREMENT,
                deck_id               INTEGER NOT NULL REFERENCES deck(id) ON DELETE CASCADE,
                sense_id              INTEGER NOT NULL,
                front_term_id         INTEGER NOT NULL,
                back_term_id          INTEGER NOT NULL,
                direction             TEXT NOT NULL,
                created_at            DATETIME NOT NULL,
                suspended             INTEGER NOT NULL DEFAULT 0,
                front_term_ids        TEXT NOT NULL DEFAULT '',
                back_term_ids         TEXT NOT NULL DEFAULT '',
                front_text_override   TEXT,
                back_text_override    TEXT
            );

            CREATE UNIQUE INDEX card_unique_idx
                ON card(deck_id, sense_id, direction);
            CREATE INDEX card_deck_idx ON card(deck_id);

            -- Numeric dictionary IDs remain the fast runtime lookup. This
            -- compact semantic snapshot lets a later dictionary rebuild remap
            -- those IDs after the legacy monolith has been deleted.
            CREATE TABLE card_dictionary_reference (
                card_id   INTEGER PRIMARY KEY REFERENCES card(id) ON DELETE CASCADE,
                format    TEXT NOT NULL,
                payload   BLOB NOT NULL
            );

            CREATE TABLE card_srs (
                card_id           INTEGER PRIMARY KEY REFERENCES card(id) ON DELETE CASCADE,
                ease              REAL NOT NULL,
                interval_days     REAL NOT NULL,
                repetitions       INTEGER NOT NULL,
                lapses            INTEGER NOT NULL,
                due_at            DATETIME NOT NULL,
                last_reviewed_at  DATETIME
            );
            CREATE INDEX card_srs_due_idx ON card_srs(due_at);

            CREATE TABLE review_log (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                card_id        INTEGER NOT NULL REFERENCES card(id) ON DELETE CASCADE,
                reviewed_at    DATETIME NOT NULL,
                grade          INTEGER NOT NULL,
                prev_interval  REAL NOT NULL,
                new_interval   REAL NOT NULL,
                prev_ease      REAL NOT NULL,
                new_ease       REAL NOT NULL
            );
            CREATE INDEX review_log_card_idx ON review_log(card_id);

            CREATE TABLE dictionary_search_history (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                query        TEXT NOT NULL,
                direction    TEXT NOT NULL,
                source_lang  TEXT NOT NULL,
                target_lang  TEXT NOT NULL,
                searched_at  DATETIME NOT NULL
            );
            CREATE UNIQUE INDEX dictionary_search_history_unique_idx
                ON dictionary_search_history(query, direction, source_lang, target_lang);
            CREATE INDEX dictionary_search_history_recent_idx
                ON dictionary_search_history(source_lang, target_lang, searched_at);

            CREATE TABLE dictionary_opened_sense_history (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                sense_id         INTEGER NOT NULL,
                matched_term_id  INTEGER NOT NULL,
                source_lang      TEXT NOT NULL,
                target_lang      TEXT NOT NULL,
                opened_at        DATETIME NOT NULL
            );
            CREATE UNIQUE INDEX dictionary_opened_sense_history_unique_idx
                ON dictionary_opened_sense_history(sense_id, source_lang, target_lang);
            CREATE INDEX dictionary_opened_sense_history_recent_idx
                ON dictionary_opened_sense_history(source_lang, target_lang, opened_at);

            PRAGMA main.user_version = 1;
            """)
    }

    static func validate(_ db: Database) throws {
        let version = try version(in: db)
        guard version == currentVersion else {
            throw AppDatabaseError.unsupportedUserDatabaseVersion(version)
        }

        let tables = Set(try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master WHERE type = 'table'
            """))
        let missing = requiredTables.subtracting(tables)
        guard missing.isEmpty else {
            throw AppDatabaseError.invalidUserDatabase(
                "Missing tables: \(missing.sorted().joined(separator: ", "))."
            )
        }

        // Always scope integrity checks to the tiny writable database. An
        // unqualified quick_check also scans attached databases, which would
        // read the entire bundled dictionary on every routine app launch.
        let check = try String.fetchOne(db, sql: "PRAGMA main.quick_check")
        guard check == "ok" else {
            throw AppDatabaseError.invalidUserDatabase(check ?? "quick_check failed")
        }

        let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA main.foreign_key_check")
        guard foreignKeyFailures.isEmpty else {
            throw AppDatabaseError.invalidUserDatabase("Foreign-key validation failed.")
        }
    }
}
