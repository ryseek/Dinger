import Foundation
import GRDB
@testable import Dinger

enum TestDatabaseSupport {
    static func makeDatabase() async throws -> AppDatabase {
        let database = try AppDatabase.makeEmptyInMemory()
        try await database.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO language (id, code) VALUES (1, 'de'), (2, 'en');
                INSERT INTO dictionary (id, source_lang_id, target_lang_id, version, name)
                VALUES (1, 1, 2, 'test', 'Test Dictionary');

                INSERT INTO entry (id, dictionary_id, raw) VALUES
                    (1, 1, 'Haus::house'),
                    (2, 1, 'Baum::tree'),
                    (3, 1, 'Katze::cat'),
                    (4, 1, 'C++::C++');

                INSERT INTO sense (id, entry_id, position) VALUES
                    (1, 1, 0),
                    (2, 2, 0),
                    (3, 3, 0),
                    (4, 4, 0);

                INSERT INTO term (id, sense_id, language_id, surface, headword, normalized, pos, gender) VALUES
                    (1, 1, 1, 'Haus {n}', 'Haus', 'haus', NULL, 'n'),
                    (2, 1, 2, 'house', 'house', 'house', NULL, NULL),
                    (3, 2, 1, 'Baum {m}', 'Baum', 'baum', NULL, 'm'),
                    (4, 2, 2, 'tree', 'tree', 'tree', NULL, NULL),
                    (5, 3, 1, 'Katze {f}', 'Katze', 'katze', NULL, 'f'),
                    (6, 3, 2, 'cat', 'cat', 'cat', NULL, NULL),
                    (7, 4, 1, 'C++', 'C++', 'c++', NULL, NULL),
                    (8, 4, 2, 'C++', 'C++', 'c++', NULL, NULL);

                INSERT INTO term_fts(term_fts) VALUES('rebuild');
                """)
        }
        return database
    }

    static func hit(_ query: String,
                    database: AppDatabase,
                    direction: LookupDirection = .sourceToTarget) async throws -> SenseHit {
        let service = DictionarySearchService(database: database)
        let options = DictionarySearchService.SearchOptions(
            limit: 20,
            direction: direction,
            pair: .deEN
        )
        guard let hit = try await service.search(query, options: options).first else {
            throw FixtureError.missingHit(query)
        }
        return hit
    }

    static func card(_ query: String,
                     deck: Deck,
                     service: CardService,
                     database: AppDatabase) async throws -> Card {
        let hit = try await hit(query, database: database)
        return try await service.createCard(
            from: hit,
            direction: .sourceToTarget,
            deck: deck
        ).card
    }

    enum FixtureError: Error {
        case missingHit(String)
    }
}
