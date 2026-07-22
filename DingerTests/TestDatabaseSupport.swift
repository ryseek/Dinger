import Foundation
import GRDB
@testable import Dinger

enum TestDatabaseSupport {
    static func makeDatabase() async throws -> AppDatabase {
        let database = try AppDatabase.makeEmptyInMemory()
        try await database.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO dict.language (id, code) VALUES (1, 'de'), (2, 'en');
                INSERT INTO dict.dictionary (id, source_lang_id, target_lang_id, version, name)
                VALUES (1, 1, 2, 'test', 'Test Dictionary');

                INSERT INTO dict.entry (id, dictionary_id, raw) VALUES
                    (1, 1, 'Haus::house'),
                    (2, 1, 'Baum::tree'),
                    (3, 1, 'Katze::cat'),
                    (4, 1, 'C++::C++'),
                    (5, 1, 'Hund::dog'),
                    (6, 1, 'Buch::book'),
                    (7, 1, 'Tisch::table'),
                    (8, 1, 'Auto::car'),
                    (9, 1, 'laufen::run'),
                    (10, 1, 'schnell::fast'),
                    (11, 1, 'Straße::street'),
                    (12, 1, 'gehen::walk'),
                    (13, 1, 'wissen::know'),
                    (14, 1, 'kennen::know'),
                    (15, 1, 'machen::do'),
                    (16, 1, 'sagen::say'),
                    (17, 1, 'sehen::see'),
                    (18, 1, 'geben::give'),
                    (19, 1, 'nehmen::take'),
                    (20, 1, 'finden::find'),
                    (21, 1, 'bleiben::stay'),
                    (22, 1, 'Carport::carport'),
                    (23, 1, 'Abwurfwagen::car');

                INSERT INTO dict.sense (id, entry_id, position) VALUES
                    (1, 1, 0),
                    (2, 2, 0),
                    (3, 3, 0),
                    (4, 4, 0),
                    (5, 5, 0),
                    (6, 6, 0),
                    (7, 7, 0),
                    (8, 8, 0),
                    (9, 9, 0),
                    (10, 10, 0),
                    (11, 11, 0),
                    (12, 12, 0),
                    (13, 13, 0),
                    (14, 14, 0),
                    (15, 15, 0),
                    (16, 16, 0),
                    (17, 17, 0),
                    (18, 18, 0),
                    (19, 19, 0),
                    (20, 20, 0),
                    (21, 21, 0),
                    (22, 22, 0),
                    (23, 23, 0);

                INSERT INTO dict.term (id, sense_id, language_id, surface, headword, normalized, pos, gender) VALUES
                    (1, 1, 1, 'Haus {n}', 'Haus', 'haus', NULL, 'n'),
                    (2, 1, 2, 'house', 'house', 'house', NULL, NULL),
                    (3, 2, 1, 'Baum {m}', 'Baum', 'baum', NULL, 'm'),
                    (4, 2, 2, 'tree', 'tree', 'tree', NULL, NULL),
                    (5, 3, 1, 'Katze {f}', 'Katze', 'katze', NULL, 'f'),
                    (6, 3, 2, 'cat', 'cat', 'cat', NULL, NULL),
                    (7, 4, 1, 'C++', 'C++', 'c++', NULL, NULL),
                    (8, 4, 2, 'C++', 'C++', 'c++', NULL, NULL),
                    (9, 5, 1, 'Hund {m}', 'Hund', 'hund', NULL, 'm'),
                    (10, 5, 2, 'dog', 'dog', 'dog', NULL, NULL),
                    (11, 6, 1, 'Buch {n}', 'Buch', 'buch', NULL, 'n'),
                    (12, 6, 2, 'book', 'book', 'book', NULL, NULL),
                    (13, 7, 1, 'Tisch {m}', 'Tisch', 'tisch', NULL, 'm'),
                    (14, 7, 2, 'table', 'table', 'table', NULL, NULL),
                    (15, 8, 1, 'Auto {n}', 'Auto', 'auto', NULL, 'n'),
                    (16, 8, 2, 'car', 'car', 'car', NULL, NULL),
                    (17, 9, 1, 'laufen', 'laufen', 'laufen', 'v/i', NULL),
                    (18, 9, 2, 'run', 'run', 'run', NULL, NULL),
                    (19, 10, 1, 'schnell', 'schnell', 'schnell', 'adj', NULL),
                    (20, 10, 2, 'fast', 'fast', 'fast', NULL, NULL),
                    (21, 11, 1, 'Straße {f}', 'Straße', 'strasse', NULL, 'f'),
                    (22, 11, 2, 'street', 'street', 'street', NULL, NULL),
                    (23, 12, 1, 'gehen', 'gehen', 'gehen', 'v/i', NULL),
                    (24, 12, 2, 'walk', 'walk', 'walk', NULL, NULL),
                    (25, 13, 1, 'wissen', 'wissen', 'wissen', 'v/i', NULL),
                    (26, 13, 2, 'know', 'know', 'know', NULL, NULL),
                    (27, 14, 1, 'kennen', 'kennen', 'kennen', 'v/t', NULL),
                    (28, 14, 2, 'know', 'know', 'know', NULL, NULL),
                    (29, 15, 1, 'machen', 'machen', 'machen', 'v/t', NULL),
                    (30, 15, 2, 'do', 'do', 'do', NULL, NULL),
                    (31, 16, 1, 'sagen', 'sagen', 'sagen', 'v/t', NULL),
                    (32, 16, 2, 'say', 'say', 'say', NULL, NULL),
                    (33, 17, 1, 'sehen', 'sehen', 'sehen', 'v/t', NULL),
                    (34, 17, 2, 'see', 'see', 'see', NULL, NULL),
                    (35, 18, 1, 'geben', 'geben', 'geben', 'v/t', NULL),
                    (36, 18, 2, 'give', 'give', 'give', NULL, NULL),
                    (37, 19, 1, 'nehmen', 'nehmen', 'nehmen', 'v/t', NULL),
                    (38, 19, 2, 'take', 'take', 'take', NULL, NULL),
                    (39, 20, 1, 'finden', 'finden', 'finden', 'v/t', NULL),
                    (40, 20, 2, 'find', 'find', 'find', NULL, NULL),
                    (41, 21, 1, 'bleiben', 'bleiben', 'bleiben', 'v/i', NULL),
                    (42, 21, 2, 'stay', 'stay', 'stay', NULL, NULL),
                    (1001, 22, 1, 'Carport {m}', 'Carport', 'carport', NULL, 'm'),
                    (1002, 22, 2, 'carport', 'carport', 'carport', NULL, NULL),
                    (1003, 23, 1, 'Abwurfwagen {m}', 'Abwurfwagen', 'abwurfwagen', NULL, 'm'),
                    (1004, 23, 2, 'car', 'car', 'car', NULL, NULL);

                INSERT INTO dict.term_fts(term_fts) VALUES('rebuild');
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
