import Foundation
import GRDB

/// Creates the dictionary tables in a freshly-opened DatabaseWriter. Kept in
/// sync with `AppDatabase.swift`'s "dictionary-schema-v1" migration; the app
/// will run the same migration but use `CREATE TABLE IF NOT EXISTS` so the
/// seeded tables are accepted as-is.
enum ImporterSchema {
    static func create(in writer: any DatabaseWriter) throws {
        try writer.write { db in
            try db.execute(sql: """
                CREATE TABLE language (
                    id   INTEGER PRIMARY KEY AUTOINCREMENT,
                    code TEXT NOT NULL UNIQUE
                );
            """)
            try db.execute(sql: """
                CREATE TABLE dictionary (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_lang_id  INTEGER NOT NULL REFERENCES language(id),
                    target_lang_id  INTEGER NOT NULL REFERENCES language(id),
                    version         TEXT NOT NULL,
                    name            TEXT NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE TABLE entry (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    dictionary_id  INTEGER NOT NULL REFERENCES dictionary(id),
                    raw            TEXT NOT NULL
                );
            """)
            try db.execute(sql: """
                CREATE TABLE sense (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    entry_id  INTEGER NOT NULL REFERENCES entry(id),
                    position  INTEGER NOT NULL,
                    domain    TEXT,
                    context   TEXT
                );
            """)
            try db.execute(sql: """
                CREATE INDEX sense_entry_idx ON sense(entry_id);
            """)
            try db.execute(sql: """
                CREATE TABLE term (
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
                CREATE INDEX term_sense_idx      ON term(sense_id);
            """)
            try db.execute(sql: """
                CREATE INDEX term_normalized_idx ON term(normalized);
            """)
            try db.execute(sql: """
                CREATE VIRTUAL TABLE term_fts USING fts5(
                    headword, normalized,
                    content='term', content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                );
            """)
        }
    }
}
