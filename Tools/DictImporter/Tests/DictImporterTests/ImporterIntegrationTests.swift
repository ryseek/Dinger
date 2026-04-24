import XCTest
import GRDB
@testable import DictImporter

/// End-to-end: run the importer against a tiny fixture .txt, then query
/// the resulting SQLite to prove parser → schema → FTS rebuild all work.
final class ImporterIntegrationTests: XCTestCase {

    func testRoundTripWithFixture() throws {
        let fixture = """
        # sample
        Abbau {m}; Demontage {f} :: breakdown; dismantling
        Abänderung {f} :: amendment
        Aal {m} | Aale {pl} :: eel | eels
        foo [x|y] :: bar
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let input = tmp.appendingPathComponent("mini.txt")
        let output = tmp.appendingPathComponent("mini.sqlite")
        try fixture.data(using: .utf8)!.write(to: input)

        let importer = Importer(
            parser: TuChemnitzParser(),
            sourceURL: input,
            outputURL: output,
            dictName: "Mini",
            dictVersion: "test"
        )
        let stats = try importer.run()
        XCTAssertEqual(stats.entries, 4)
        XCTAssertGreaterThan(stats.terms, 5)

        let queue = try DatabaseQueue(path: output.path)
        try queue.read { db in
            // Exact normalized lookup.
            let countAb = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM term WHERE normalized = ?",
                arguments: ["abaenderung"]) ?? 0
            XCTAssertGreaterThan(countAb, 0, "umlaut-folded normalized should match Abänderung")

            // FTS5 prefix search against the shadow index.
            let ftsCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM term_fts WHERE term_fts MATCH ?
                """, arguments: ["abbau*"]) ?? 0
            XCTAssertGreaterThan(ftsCount, 0)

            // Multi-group alignment: Aal / Aale produce two senses.
            let aalSenses = try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT s.id) FROM sense s
                JOIN term t ON t.sense_id = s.id
                WHERE t.normalized IN ('aal', 'aale')
                """) ?? 0
            XCTAssertEqual(aalSenses, 2)

            // Bracketed pipe does not split groups: "foo [x|y]" should be 1 sense.
            let fooSenses = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sense s
                JOIN entry e ON e.id = s.entry_id
                WHERE e.raw LIKE 'foo %'
                """) ?? 0
            XCTAssertEqual(fooSenses, 1)
        }

        try? FileManager.default.removeItem(at: tmp)
    }
}
