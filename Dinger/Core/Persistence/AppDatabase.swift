import Foundation
import GRDB

/// Owns the small writable user database. The production dictionary remains
/// in the application bundle and is attached to every connection as the
/// read-only `dict` schema.
public nonisolated final class AppDatabase: @unchecked Sendable {
    public let dbWriter: any DatabaseWriter

    public nonisolated enum StartupProgress: Sendable, Equatable {
        case creatingUserDatabase
        case migratingLegacyDatabase
        case migratingSchema
        case cleaningLegacyDatabase

        public var title: String {
            switch self {
            case .creatingUserDatabase:
                return "Preparing your library..."
            case .migratingLegacyDatabase:
                return "Moving your learning data..."
            case .migratingSchema:
                return "Updating database..."
            case .cleaningLegacyDatabase:
                return "Finishing storage cleanup..."
            }
        }

        public var detail: String? { nil }
        public var fractionCompleted: Double? { nil }
    }

    public init(_ dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    // MARK: - File layout

    public static let dictionaryResourceName = "de-en"
    public static let dictionaryResourceExt = "sqlite"
    public static let userFileName = "user.sqlite"
    public static let legacyFileName = "dinger.sqlite"
    static let migrationFileName = "user.sqlite.migrating"

    public static func databaseDirectory() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Dinger", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func userDatabaseURL() throws -> URL {
        try databaseDirectory().appendingPathComponent(userFileName)
    }

    /// Compatibility accessor for callers that previously requested the only
    /// on-device database. It now returns the small user database.
    public static func onDeviceURL() throws -> URL {
        try userDatabaseURL()
    }

    // MARK: - Production bootstrap

    public static func makeShared(progress: ((StartupProgress) -> Void)? = nil) throws -> AppDatabase {
        guard let dictionaryURL = Bundle.main.url(
            forResource: dictionaryResourceName,
            withExtension: dictionaryResourceExt
        ) else {
            throw AppDatabaseError.seedMissing
        }
        return try makeShared(
            dictionaryURL: dictionaryURL,
            databaseDirectory: databaseDirectory(),
            progress: progress
        )
    }

    /// Testable bootstrap entry point. Production supplies the bundle resource
    /// and Application Support directory; migration tests use isolated files.
    static func makeShared(dictionaryURL: URL,
                           databaseDirectory: URL,
                           progress: ((StartupProgress) -> Void)? = nil) throws -> AppDatabase {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)

        let userURL = databaseDirectory.appendingPathComponent(userFileName)
        let legacyURL = databaseDirectory.appendingPathComponent(legacyFileName)
        let migrationURL = databaseDirectory.appendingPathComponent(migrationFileName)
        let userDatabaseAlreadyExists = fileManager.fileExists(atPath: userURL.path)
        var migratedLegacyThisLaunch = false

        if !userDatabaseAlreadyExists {
            try removeSQLiteFiles(at: migrationURL)
            if fileManager.fileExists(atPath: legacyURL.path) {
                progress?(.migratingLegacyDatabase)
                try LegacyDatabaseImporter.importDatabase(
                    from: legacyURL,
                    to: migrationURL,
                    dictionaryURL: dictionaryURL
                )
                try fileManager.moveItem(at: migrationURL, to: userURL)
                try removeSQLiteFiles(at: migrationURL)
                migratedLegacyThisLaunch = true
            } else {
                progress?(.creatingUserDatabase)
                try UserDatabaseSchema.createFresh(at: migrationURL)
                try fileManager.moveItem(at: migrationURL, to: userURL)
                try removeSQLiteFiles(at: migrationURL)
            }
        }

        var configuration = Configuration()
        let dictionaryURI = readOnlySQLiteURI(for: dictionaryURL, immutable: true)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(
                sql: "ATTACH DATABASE ? AS dict",
                arguments: [dictionaryURI]
            )
        }

        let pool = try DatabasePool(path: userURL.path, configuration: configuration)
        try pool.writeWithoutTransaction { db in
            if userDatabaseAlreadyExists {
                if try UserDatabaseSchema.version(in: db) < UserDatabaseSchema.currentVersion {
                    progress?(.migratingSchema)
                }
                try UserDatabaseSchema.prepareExisting(in: db)
            }
            try validateDictionary(db)
            try UserDatabaseSchema.validate(db)
        }
        let database = AppDatabase(pool)

        if migratedLegacyThisLaunch {
            // This marker is written only after the activated pool and bundled
            // dictionary have both opened successfully. Cleanup intentionally
            // waits for a later successful launch.
            try pool.write { db in
                try setMetadata("legacy_activation_confirmed", value: "1", db: db)
            }
        } else if try cleanupIsPending(in: pool) {
            progress?(.cleaningLegacyDatabase)
            do {
                try removeSQLiteFiles(at: legacyURL)
                try pool.write { db in
                    try setMetadata("legacy_cleanup_pending", value: "0", db: db)
                }
            } catch {
                // Cleanup is reclaimable housekeeping, never a reason to keep
                // the user out of an already validated database. The pending
                // marker makes a later launch retry any remaining sidecars.
                NSLog("Deferred legacy database cleanup failed: %@", error.localizedDescription)
            }
        }

        return database
    }

    // MARK: - In-memory test database

    /// A single-connection split database used by unit tests and previews.
    public static func makeEmptyInMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue()
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "ATTACH DATABASE ':memory:' AS dict")
            try db.inTransaction {
                try UserDatabaseSchema.createCurrent(in: db)
                try createTestDictionarySchema(in: db)
                return .commit
            }
        }
        return AppDatabase(queue)
    }

    private static func createTestDictionarySchema(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE dict.language (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL UNIQUE
            );
            CREATE TABLE dict.dictionary (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_lang_id INTEGER NOT NULL REFERENCES language(id),
                target_lang_id INTEGER NOT NULL REFERENCES language(id),
                version TEXT NOT NULL,
                name TEXT NOT NULL
            );
            CREATE TABLE dict.entry (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                dictionary_id INTEGER NOT NULL REFERENCES dictionary(id),
                raw TEXT NOT NULL
            );
            CREATE TABLE dict.sense (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entry_id INTEGER NOT NULL REFERENCES entry(id),
                position INTEGER NOT NULL,
                domain TEXT,
                context TEXT
            );
            CREATE INDEX dict.sense_entry_idx ON sense(entry_id);
            CREATE TABLE dict.term (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sense_id INTEGER NOT NULL REFERENCES sense(id),
                language_id INTEGER NOT NULL REFERENCES language(id),
                surface TEXT NOT NULL,
                headword TEXT NOT NULL,
                normalized TEXT NOT NULL,
                pos TEXT,
                gender TEXT
            );
            CREATE INDEX dict.term_sense_idx ON term(sense_id);
            CREATE INDEX dict.term_normalized_idx ON term(normalized);
            CREATE VIRTUAL TABLE dict.term_fts USING fts5(
                headword, normalized,
                content='term', content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE TABLE dict.example_sentence (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                de_tatoeba_id INTEGER NOT NULL,
                en_tatoeba_id INTEGER NOT NULL,
                de_text TEXT NOT NULL,
                en_text TEXT NOT NULL,
                de_normalized TEXT NOT NULL,
                en_normalized TEXT NOT NULL,
                UNIQUE(de_tatoeba_id, en_tatoeba_id)
            );
            CREATE VIRTUAL TABLE dict.example_sentence_fts USING fts5(
                de_normalized, en_normalized,
                content='example_sentence', content_rowid='id',
                tokenize='unicode61 remove_diacritics 2'
            );
            """)
    }

    // MARK: - Validation, cleanup, and SQLite helpers

    static func readOnlySQLiteURI(for url: URL, immutable: Bool) -> String {
        var result = url.absoluteString
        result += result.contains("?") ? "&mode=ro" : "?mode=ro"
        if immutable { result += "&immutable=1" }
        return result
    }

    private static func validateDictionary(_ db: Database) throws {
        let required = [
            "language", "dictionary", "entry", "sense", "term", "term_fts",
            "example_sentence", "example_sentence_fts",
        ]
        let available = Set(try String.fetchAll(db, sql: """
            SELECT name FROM dict.sqlite_master WHERE type = 'table'
            """))
        let missing = Set(required).subtracting(available)
        guard missing.isEmpty else {
            throw AppDatabaseError.invalidDictionary(
                "Missing tables: \(missing.sorted().joined(separator: ", "))."
            )
        }

        // A tiny indexed lookup verifies that the attachment is queryable
        // without scanning the 352 MiB resource on every launch.
        guard try Int.fetchOne(db, sql: "SELECT id FROM dict.dictionary LIMIT 1") != nil else {
            throw AppDatabaseError.invalidDictionary("No dictionary metadata was found.")
        }
    }

    private static func cleanupIsPending(in writer: any DatabaseWriter) throws -> Bool {
        try writer.read { db in
            let pending = try String.fetchOne(
                db,
                sql: "SELECT value FROM app_metadata WHERE key = 'legacy_cleanup_pending'"
            )
            let confirmed = try String.fetchOne(
                db,
                sql: "SELECT value FROM app_metadata WHERE key = 'legacy_activation_confirmed'"
            )
            return pending == "1" && confirmed == "1"
        }
    }

    private static func setMetadata(_ key: String, value: String, db: Database) throws {
        try db.execute(sql: """
            INSERT INTO app_metadata (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, arguments: [key, value])
    }

    private static func removeSQLiteFiles(at url: URL) throws {
        let fileManager = FileManager.default
        for candidate in [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ] where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }
}

public nonisolated enum AppDatabaseError: Error, LocalizedError {
    case seedMissing
    case invalidDictionary(String)
    case invalidUserDatabase(String)
    case unsupportedUserDatabaseVersion(Int)
    case invalidLegacyDatabase(String)
    case unresolvedDictionaryReference(String)

    public var errorDescription: String? {
        switch self {
        case .seedMissing:
            return "Bundled dictionary seed (de-en.sqlite) is missing from the app bundle."
        case .invalidDictionary(let detail):
            return "The bundled dictionary is invalid: \(detail)"
        case .invalidUserDatabase(let detail):
            return "Your learning database is invalid: \(detail)"
        case .unsupportedUserDatabaseVersion(let version):
            return "This learning database uses unsupported schema version \(version)."
        case .invalidLegacyDatabase(let detail):
            return "Your existing learning data could not be migrated: \(detail)"
        case .unresolvedDictionaryReference(let detail):
            return "An existing card could not be matched to the bundled dictionary: \(detail)"
        }
    }
}
