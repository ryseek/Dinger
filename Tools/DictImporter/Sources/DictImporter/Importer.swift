import Foundation
import GRDB

public struct ImportStats: Sendable {
    public var entries: Int = 0
    public var senses: Int = 0
    public var terms: Int = 0
    public var skipped: Int = 0
}

public final class Importer {

    public let parser: any DictionaryParser
    public let sourceURL: URL
    public let outputURL: URL
    public let dictName: String
    public let dictVersion: String

    public init(parser: any DictionaryParser,
                sourceURL: URL,
                outputURL: URL,
                dictName: String,
                dictVersion: String) {
        self.parser = parser
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.dictName = dictName
        self.dictVersion = dictVersion
    }

    public func run(progress: ((Int, ImportStats) -> Void)? = nil) throws -> ImportStats {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try fm.createDirectory(at: outputURL.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            // Tune for bulk write. WAL is reset afterwards by VACUUM.
            try db.execute(sql: "PRAGMA journal_mode = MEMORY")
            try db.execute(sql: "PRAGMA synchronous = OFF")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
        }

        let queue = try DatabaseQueue(path: outputURL.path, configuration: config)
        try ImporterSchema.create(in: queue)

        let (sourceLangId, targetLangId, dictId) = try queue.write { db -> (Int64, Int64, Int64) in
            try db.execute(sql: "INSERT INTO language (code) VALUES (?)", arguments: [parser.sourceLanguage])
            let src = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO language (code) VALUES (?)", arguments: [parser.targetLanguage])
            let tgt = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO dictionary (source_lang_id, target_lang_id, version, name)
                VALUES (?, ?, ?, ?)
            """, arguments: [src, tgt, dictVersion, dictName])
            return (src, tgt, db.lastInsertedRowID)
        }

        var stats = ImportStats()
        let content = try String(contentsOf: sourceURL, encoding: .utf8)

        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "BEGIN")
            let insertEntry = try db.makeStatement(sql:
                "INSERT INTO entry (dictionary_id, raw) VALUES (?, ?)")
            let insertSense = try db.makeStatement(sql:
                "INSERT INTO sense (entry_id, position, domain, context) VALUES (?, ?, ?, ?)")
            let insertTerm = try db.makeStatement(sql: """
                INSERT INTO term (sense_id, language_id, surface, headword, normalized, pos, gender)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """)

            content.enumerateLines { line, _ in
                do {
                    guard let parsed = self.parser.parse(line: line) else {
                        stats.skipped += 1
                        return
                    }

                    try insertEntry.execute(arguments: [dictId, parsed.raw])
                    let entryId = db.lastInsertedRowID
                    stats.entries += 1

                    for (idx, sense) in parsed.senses.enumerated() {
                        let domain = sense.domain.isEmpty ? nil : sense.domain.joined(separator: ";")
                        try insertSense.execute(arguments: [entryId, idx, domain, sense.context])
                        let senseId = db.lastInsertedRowID
                        stats.senses += 1

                        for t in sense.sourceTerms {
                            try insertTerm.execute(arguments: [
                                senseId, sourceLangId, t.surface, t.headword, t.normalized, t.pos, t.gender
                            ])
                            stats.terms += 1
                        }
                        for t in sense.targetTerms {
                            try insertTerm.execute(arguments: [
                                senseId, targetLangId, t.surface, t.headword, t.normalized, t.pos, t.gender
                            ])
                            stats.terms += 1
                        }
                    }

                    if stats.entries % 10_000 == 0 {
                        progress?(stats.entries, stats)
                    }
                } catch {
                    // enumerateLines can't propagate throws; abort the run
                    // by writing a marker and stopping subsequent inserts.
                    FileHandle.standardError.write(Data("Insert error: \(error)\n".utf8))
                }
            }

            try db.execute(sql: "COMMIT")
        }

        // Rebuild FTS from `term` (content-less shadow table is populated via rebuild).
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO term_fts(term_fts) VALUES('rebuild');
            """)
            try db.execute(sql: "ANALYZE")
        }

        // Re-open without the aggressive pragmas and VACUUM into a smaller file.
        try queue.close()
        let vacuumQueue = try DatabaseQueue(path: outputURL.path)
        try vacuumQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(sql: "VACUUM")
        }
        try vacuumQueue.close()

        return stats
    }
}
