import Foundation
import GRDB
import XCTest
@testable import Dinger

final class DatabaseCutoverTests: XCTestCase {
    private nonisolated enum LegacyShape: CaseIterable {
        case initial
        case selectedTerms
        case current
    }

    func testFreshInstallCreatesCurrentSmallUserDatabaseWithoutHistoricalMigrations() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionaryURL = directory.appendingPathComponent("dictionary.sqlite")
        try makeDictionary(at: dictionaryURL)

        var progress: [AppDatabase.StartupProgress] = []
        let database = try AppDatabase.makeShared(
            dictionaryURL: dictionaryURL,
            databaseDirectory: directory,
            progress: { progress.append($0) }
        )
        let userURL = directory.appendingPathComponent(AppDatabase.userFileName)

        XCTAssertTrue(FileManager.default.fileExists(atPath: userURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(AppDatabase.legacyFileName).path
        ))
        XCTAssertTrue(progress.contains(.creatingUserDatabase))
        XCTAssertFalse(progress.contains(.migratingLegacyDatabase))

        try await database.dbWriter.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "PRAGMA main.user_version"),
                UserDatabaseSchema.currentVersion
            )
            XCTAssertEqual(
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM main.sqlite_master
                     WHERE type = 'table' AND name = 'grdb_migrations'
                    """),
                0
            )
            XCTAssertEqual(
                try String.fetchOne(db, sql: "SELECT surface FROM dict.term WHERE id = 900"),
                "Haus {n}"
            )
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: userURL.path)
        let byteCount = attributes[.size] as? NSNumber
        XCTAssertLessThan(byteCount?.intValue ?? .max, 256 * 1_024)

        do {
            try await database.dbWriter.write { db in
                try db.execute(sql: "UPDATE dict.term SET surface = 'changed' WHERE id = 900")
            }
            XCTFail("The bundled dictionary attachment must be read-only")
        } catch {
            // Expected: `dict` was attached with mode=ro and immutable=1.
        }

        var reopenProgress: [AppDatabase.StartupProgress] = []
        _ = try AppDatabase.makeShared(
            dictionaryURL: dictionaryURL,
            databaseDirectory: directory,
            progress: { reopenProgress.append($0) }
        )
        XCTAssertTrue(
            reopenProgress.isEmpty,
            "A routine launch should not surface internal database-opening steps."
        )
    }

    func testEveryReleasedLegacyShapeMigratesAndCleansUpOnLaterLaunch() async throws {
        for shape in LegacyShape.allCases {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let dictionaryURL = directory.appendingPathComponent("dictionary.sqlite")
            let legacyURL = directory.appendingPathComponent(AppDatabase.legacyFileName)
            try makeDictionary(at: dictionaryURL)
            try makeLegacyDatabase(at: legacyURL, shape: shape)

            let database = try AppDatabase.makeShared(
                dictionaryURL: dictionaryURL,
                databaseDirectory: directory
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

            try await database.dbWriter.read { db in
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deck"), 1)
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM card"), 1)
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM card_srs"), 1)
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM review_log"), 1)
                XCTAssertEqual(
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_search_history"),
                    1
                )
                XCTAssertEqual(
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictionary_opened_sense_history"),
                    1
                )
                XCTAssertEqual(
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM card_dictionary_reference"),
                    1
                )

                let card = try XCTUnwrap(Card.fetchOne(db, key: 41))
                XCTAssertEqual(card.senseId, 800)
                XCTAssertEqual(card.frontTermId, 900)
                XCTAssertEqual(card.backTermId, 901)
                XCTAssertEqual(
                    card.frontTermIds,
                    shape == .initial ? [900] : [900, 902]
                )
                XCTAssertEqual(card.backTermIds, [901])
                XCTAssertEqual(card.frontTextOverride, shape == .current ? "my house" : nil)
                XCTAssertEqual(card.backTextOverride, shape == .current ? "home" : nil)

                let opened = try XCTUnwrap(DictionaryOpenedSenseHistoryItem.fetchOne(db, key: 71))
                XCTAssertEqual(opened.senseId, 800)
                XCTAssertEqual(opened.matchedTermId, 900)
            }

            // A second successful open proves the activated database can be
            // trusted before the large legacy file and sidecars are removed.
            _ = try AppDatabase.makeShared(
                dictionaryURL: dictionaryURL,
                databaseDirectory: directory
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(AppDatabase.userFileName).path
            ))
        }
    }

    func testFailedMigrationKeepsLegacyAndRetryDiscardsPartialDestination() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionaryURL = directory.appendingPathComponent("dictionary.sqlite")
        let legacyURL = directory.appendingPathComponent(AppDatabase.legacyFileName)
        let userURL = directory.appendingPathComponent(AppDatabase.userFileName)
        let partialURL = directory.appendingPathComponent("user.sqlite.migrating")
        try makeDictionary(at: dictionaryURL, entryRaw: "different::entry")
        try makeLegacyDatabase(at: legacyURL, shape: .current)

        XCTAssertThrowsError(try AppDatabase.makeShared(
            dictionaryURL: dictionaryURL,
            databaseDirectory: directory
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: userURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: partialURL.path))

        try FileManager.default.removeItem(at: dictionaryURL)
        try makeDictionary(at: dictionaryURL)
        let recovered = try AppDatabase.makeShared(
            dictionaryURL: dictionaryURL,
            databaseDirectory: directory
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        let recoveredCardCount = try await recovered.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM card")
        }
        XCTAssertEqual(recoveredCardCount, 1)
    }

    // MARK: - Fixtures

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DingerDatabaseCutover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDictionary(at url: URL, entryRaw: String = "Haus::house") throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE language (
                    id INTEGER PRIMARY KEY,
                    code TEXT NOT NULL UNIQUE
                );
                CREATE TABLE dictionary (
                    id INTEGER PRIMARY KEY,
                    source_lang_id INTEGER NOT NULL,
                    target_lang_id INTEGER NOT NULL,
                    version TEXT NOT NULL,
                    name TEXT NOT NULL
                );
                CREATE TABLE entry (
                    id INTEGER PRIMARY KEY,
                    dictionary_id INTEGER NOT NULL,
                    raw TEXT NOT NULL
                );
                CREATE TABLE sense (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    position INTEGER NOT NULL,
                    domain TEXT,
                    context TEXT
                );
                CREATE TABLE term (
                    id INTEGER PRIMARY KEY,
                    sense_id INTEGER NOT NULL,
                    language_id INTEGER NOT NULL,
                    surface TEXT NOT NULL,
                    headword TEXT NOT NULL,
                    normalized TEXT NOT NULL,
                    pos TEXT,
                    gender TEXT
                );
                CREATE VIRTUAL TABLE term_fts USING fts5(
                    headword, normalized, content='term', content_rowid='id'
                );
                CREATE TABLE example_sentence (
                    id INTEGER PRIMARY KEY,
                    de_tatoeba_id INTEGER NOT NULL,
                    en_tatoeba_id INTEGER NOT NULL,
                    de_text TEXT NOT NULL,
                    en_text TEXT NOT NULL,
                    de_normalized TEXT NOT NULL,
                    en_normalized TEXT NOT NULL
                );
                CREATE VIRTUAL TABLE example_sentence_fts USING fts5(
                    de_normalized, en_normalized,
                    content='example_sentence', content_rowid='id'
                );

                INSERT INTO language VALUES (101, 'de'), (102, 'en');
                INSERT INTO dictionary VALUES (11, 101, 102, 'fixture-v2', 'Fixture');
                INSERT INTO entry VALUES (700, 11, ?);
                INSERT INTO sense VALUES (800, 700, 0, NULL, NULL);
                INSERT INTO term VALUES
                    (900, 800, 101, 'Haus {n}', 'Haus', 'haus', NULL, 'n'),
                    (901, 800, 102, 'house', 'house', 'house', NULL, NULL),
                    (902, 800, 101, 'Gebäude {n}', 'Gebäude', 'gebaude', NULL, 'n');
                INSERT INTO term_fts(term_fts) VALUES('rebuild');
                """, arguments: [entryRaw])
        }
        try queue.close()
    }

    private func makeLegacyDatabase(at url: URL, shape: LegacyShape) throws {
        let queue = try DatabaseQueue(path: url.path)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE language (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE);
                CREATE TABLE dictionary (
                    id INTEGER PRIMARY KEY,
                    source_lang_id INTEGER NOT NULL,
                    target_lang_id INTEGER NOT NULL,
                    version TEXT NOT NULL,
                    name TEXT NOT NULL
                );
                CREATE TABLE entry (id INTEGER PRIMARY KEY, dictionary_id INTEGER NOT NULL, raw TEXT NOT NULL);
                CREATE TABLE sense (
                    id INTEGER PRIMARY KEY,
                    entry_id INTEGER NOT NULL,
                    position INTEGER NOT NULL,
                    domain TEXT,
                    context TEXT
                );
                CREATE TABLE term (
                    id INTEGER PRIMARY KEY,
                    sense_id INTEGER NOT NULL,
                    language_id INTEGER NOT NULL,
                    surface TEXT NOT NULL,
                    headword TEXT NOT NULL,
                    normalized TEXT NOT NULL,
                    pos TEXT,
                    gender TEXT
                );

                CREATE TABLE deck (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    source_lang TEXT NOT NULL,
                    target_lang TEXT NOT NULL,
                    created_at DATETIME NOT NULL
                );
                CREATE TABLE card (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    deck_id INTEGER NOT NULL REFERENCES deck(id) ON DELETE CASCADE,
                    sense_id INTEGER NOT NULL,
                    front_term_id INTEGER NOT NULL,
                    back_term_id INTEGER NOT NULL,
                    direction TEXT NOT NULL,
                    created_at DATETIME NOT NULL,
                    suspended INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE card_srs (
                    card_id INTEGER PRIMARY KEY REFERENCES card(id) ON DELETE CASCADE,
                    ease REAL NOT NULL,
                    interval_days REAL NOT NULL,
                    repetitions INTEGER NOT NULL,
                    lapses INTEGER NOT NULL,
                    due_at DATETIME NOT NULL,
                    last_reviewed_at DATETIME
                );
                CREATE TABLE review_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    card_id INTEGER NOT NULL REFERENCES card(id) ON DELETE CASCADE,
                    reviewed_at DATETIME NOT NULL,
                    grade INTEGER NOT NULL,
                    prev_interval REAL NOT NULL,
                    new_interval REAL NOT NULL,
                    prev_ease REAL NOT NULL,
                    new_ease REAL NOT NULL
                );
                CREATE TABLE dictionary_search_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    query TEXT NOT NULL,
                    direction TEXT NOT NULL,
                    source_lang TEXT NOT NULL,
                    target_lang TEXT NOT NULL,
                    searched_at DATETIME NOT NULL
                );
                CREATE TABLE dictionary_opened_sense_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sense_id INTEGER NOT NULL,
                    matched_term_id INTEGER NOT NULL,
                    source_lang TEXT NOT NULL,
                    target_lang TEXT NOT NULL,
                    opened_at DATETIME NOT NULL
                );
                """)

            if shape != .initial {
                try db.execute(sql: """
                    ALTER TABLE card ADD COLUMN front_term_ids TEXT NOT NULL DEFAULT '';
                    ALTER TABLE card ADD COLUMN back_term_ids TEXT NOT NULL DEFAULT '';
                    """)
            }
            if shape == .current {
                try db.execute(sql: """
                    ALTER TABLE card ADD COLUMN front_text_override TEXT;
                    ALTER TABLE card ADD COLUMN back_text_override TEXT;
                    """)
            }

            try db.execute(sql: """
                INSERT INTO language VALUES (1, 'de'), (2, 'en');
                INSERT INTO dictionary VALUES (1, 1, 2, 'legacy', 'Legacy');
                INSERT INTO entry VALUES (10, 1, 'Haus::house');
                INSERT INTO sense VALUES (20, 10, 0, NULL, NULL);
                INSERT INTO term VALUES
                    (1, 20, 1, 'Haus {n}', 'Haus', 'haus', NULL, 'n'),
                    (2, 20, 2, 'house', 'house', 'house', NULL, NULL),
                    (3, 20, 1, 'Gebäude {n}', 'Gebäude', 'gebaude', NULL, 'n');
                """)
            try db.execute(
                sql: "INSERT INTO deck VALUES (31, 'Migrated', 'de', 'en', ?)",
                arguments: [now]
            )

            let selectedColumns = shape == .initial ? "" : ", front_term_ids, back_term_ids"
            let selectedValues = shape == .initial ? "" : ", '1,3', '2'"
            let overrideColumns = shape == .current
                ? ", front_text_override, back_text_override"
                : ""
            let overrideValues = shape == .current ? ", 'my house', 'home'" : ""
            try db.execute(sql: """
                INSERT INTO card
                    (id, deck_id, sense_id, front_term_id, back_term_id,
                     direction, created_at, suspended\(selectedColumns)\(overrideColumns))
                VALUES (41, 31, 20, 1, 2, 's2t', ?, 1\(selectedValues)\(overrideValues))
                """, arguments: [now])
            try db.execute(sql: """
                INSERT INTO card_srs VALUES (41, 2.6, 8, 3, 1, ?, ?)
                """, arguments: [now.addingTimeInterval(86_400), now])
            try db.execute(sql: """
                INSERT INTO review_log VALUES (51, 41, ?, 2, 4, 8, 2.5, 2.6)
                """, arguments: [now])
            try db.execute(sql: """
                INSERT INTO dictionary_search_history
                    VALUES (61, 'Haus', 'sourceToTarget', 'de', 'en', ?)
                """, arguments: [now])
            try db.execute(sql: """
                INSERT INTO dictionary_opened_sense_history
                    VALUES (71, 20, 1, 'de', 'en', ?)
                """, arguments: [now])
        }
        try queue.close()
    }
}
