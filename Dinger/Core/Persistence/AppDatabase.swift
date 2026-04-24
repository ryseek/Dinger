import Foundation
import GRDB

/// Owns the `DatabasePool` and applies schema migrations. The dictionary seed
/// is shipped in the app bundle as a pre-built read-only SQLite; on first launch
/// we copy it to Application Support so the app can extend it with the user's
/// cards/decks/SRS tables via GRDB migrations.
///
/// `nonisolated` so it can be used from any actor context. GRDB's pool
/// methods dispatch to their own serial queues.
public nonisolated final class AppDatabase: @unchecked Sendable {

    public let dbWriter: any DatabaseWriter

    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
    }

    // MARK: - File layout

    /// Name of the seed database bundled with the app.
    public static let seedResourceName = "de-en"
    public static let seedResourceExt  = "sqlite"

    /// Final on-device DB file name.
    public static let onDeviceFileName = "dinger.sqlite"

    public static func onDeviceURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory,
                              in: .userDomainMask,
                              appropriateFor: nil,
                              create: true)
        let dir = base.appendingPathComponent("Dinger", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(onDeviceFileName)
    }

    /// Copies the bundled seed DB into Application Support on first launch.
    /// Returns the URL of the writable on-device DB.
    public static func ensureOnDeviceSeed(in bundle: Bundle = .main) throws -> URL {
        let dest = try onDeviceURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { return dest }

        guard let seed = bundle.url(forResource: seedResourceName, withExtension: seedResourceExt) else {
            throw AppDatabaseError.seedMissing
        }
        try fm.copyItem(at: seed, to: dest)
        return dest
    }

    /// Open the production database: seed-or-copy, then open pool + migrate.
    public static func makeShared() throws -> AppDatabase {
        let url = try ensureOnDeviceSeed()
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        return try AppDatabase(pool)
    }

    /// In-memory database used by previews / tests that don't need a seeded dict.
    public static func makeEmptyInMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: Configuration())
        return try AppDatabase(queue)
    }

    // MARK: - Migrations

    /// The migrator applies BOTH the dictionary schema (idempotent: the seed
    /// already has these tables, so these CREATEs use `IF NOT EXISTS`) AND the
    /// user tables. This means an empty DB and a seeded DB both end up with
    /// identical schemas.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("dictionary-schema-v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS language (
                    id   INTEGER PRIMARY KEY AUTOINCREMENT,
                    code TEXT NOT NULL UNIQUE
                );
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS dictionary (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_lang_id  INTEGER NOT NULL REFERENCES language(id),
                    target_lang_id  INTEGER NOT NULL REFERENCES language(id),
                    version         TEXT NOT NULL,
                    name            TEXT NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS entry (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    dictionary_id  INTEGER NOT NULL REFERENCES dictionary(id),
                    raw            TEXT NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS sense (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    entry_id  INTEGER NOT NULL REFERENCES entry(id),
                    position  INTEGER NOT NULL,
                    domain    TEXT,
                    context   TEXT
                );
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS sense_entry_idx ON sense(entry_id);
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS term (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    sense_id     INTEGER NOT NULL REFERENCES sense(id),
                    language_id  INTEGER NOT NULL REFERENCES language(id),
                    surface      TEXT NOT NULL,
                    headword     TEXT NOT NULL,
                    normalized   TEXT NOT NULL,
                    pos          TEXT,
                    gender       TEXT
                );
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS term_sense_idx      ON term(sense_id);
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS term_normalized_idx ON term(normalized);
            """)
            // FTS5 shadow index on normalized + headword. Populated by the
            // importer; at runtime we treat it as read-only.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS term_fts USING fts5(
                    headword, normalized,
                    content='term', content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                );
            """)
        }

        migrator.registerMigration("user-schema-v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS deck (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    name         TEXT NOT NULL,
                    source_lang  TEXT NOT NULL,
                    target_lang  TEXT NOT NULL,
                    created_at   DATETIME NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS card (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    deck_id         INTEGER NOT NULL REFERENCES deck(id) ON DELETE CASCADE,
                    sense_id        INTEGER NOT NULL,
                    front_term_id   INTEGER NOT NULL,
                    back_term_id    INTEGER NOT NULL,
                    direction       TEXT NOT NULL,
                    created_at      DATETIME NOT NULL,
                    suspended       INTEGER NOT NULL DEFAULT 0
                );
            """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS card_unique_idx
                    ON card(deck_id, sense_id, direction);
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS card_deck_idx ON card(deck_id);
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS card_srs (
                    card_id           INTEGER PRIMARY KEY REFERENCES card(id) ON DELETE CASCADE,
                    ease              REAL NOT NULL,
                    interval_days     REAL NOT NULL,
                    repetitions       INTEGER NOT NULL,
                    lapses            INTEGER NOT NULL,
                    due_at            DATETIME NOT NULL,
                    last_reviewed_at  DATETIME
                );
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS card_srs_due_idx ON card_srs(due_at);
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS review_log (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    card_id        INTEGER NOT NULL REFERENCES card(id) ON DELETE CASCADE,
                    reviewed_at    DATETIME NOT NULL,
                    grade          INTEGER NOT NULL,
                    prev_interval  REAL NOT NULL,
                    new_interval   REAL NOT NULL,
                    prev_ease      REAL NOT NULL,
                    new_ease       REAL NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS review_log_card_idx ON review_log(card_id);
            """)
        }

        migrator.registerMigration("dictionary-history-v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS dictionary_search_history (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    query        TEXT NOT NULL,
                    direction    TEXT NOT NULL,
                    source_lang  TEXT NOT NULL,
                    target_lang  TEXT NOT NULL,
                    searched_at  DATETIME NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS dictionary_search_history_unique_idx
                    ON dictionary_search_history(query, direction, source_lang, target_lang);
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS dictionary_search_history_recent_idx
                    ON dictionary_search_history(source_lang, target_lang, searched_at);
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS dictionary_opened_sense_history (
                    id               INTEGER PRIMARY KEY AUTOINCREMENT,
                    sense_id         INTEGER NOT NULL,
                    matched_term_id  INTEGER NOT NULL,
                    source_lang      TEXT NOT NULL,
                    target_lang      TEXT NOT NULL,
                    opened_at        DATETIME NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS dictionary_opened_sense_history_unique_idx
                    ON dictionary_opened_sense_history(sense_id, source_lang, target_lang);
            """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS dictionary_opened_sense_history_recent_idx
                    ON dictionary_opened_sense_history(source_lang, target_lang, opened_at);
            """)
        }

        return migrator
    }
}

public nonisolated enum AppDatabaseError: Error, LocalizedError {
    case seedMissing

    public var errorDescription: String? {
        switch self {
        case .seedMissing:
            return "Bundled dictionary seed (de-en.sqlite) is missing from the app bundle."
        }
    }
}
