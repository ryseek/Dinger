import Foundation
import XCTest
@testable import DingerCore

final class DingerBridgeEngineTests: XCTestCase {
    func testJSONBoundaryCoversDictionaryCardsAndQuiz() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let engine = DingerBridgeEngine(database: database)

        let bootstrap = try await call(engine, ["action": "bootstrap"])
        XCTAssertEqual(bootstrap["ok"] as? Bool, true)
        XCTAssertFalse(try arrayData(bootstrap, key: "decks").isEmpty)

        let search = try await call(engine, ["action": "search", "query": "Haus", "direction": "auto"])
        let hit = try XCTUnwrap(try dataArray(search).first as? [String: Any])
        XCTAssertEqual(hit["senseId"] as? Int, 1)

        let entry = try await call(engine, [
            "action": "openSense",
            "senseId": try XCTUnwrap(hit["senseId"]),
            "matchedTermId": try XCTUnwrap(hit["matchedTermId"]),
        ])
        XCTAssertEqual(try dataObject(entry)["hit"].flatMap { ($0 as? [String: Any])?["senseId"] } as? Int, 1)

        let created = try await call(engine, ["action": "createDeck", "name": "Android"])
        let deckId = try XCTUnwrap(try dataObject(created)["id"] as? Int)
        let saved = try await call(engine, [
            "action": "saveCard",
            "senseId": try XCTUnwrap(hit["senseId"]),
            "matchedTermId": try XCTUnwrap(hit["matchedTermId"]),
            "deckId": deckId,
            "sourceTermIds": [1],
            "targetTermIds": [2],
            "cardDirection": "s2t",
        ])
        XCTAssertEqual(try dataObject(saved)["isNew"] as? Bool, true)

        let detail = try await call(engine, ["action": "deckDetail", "deckId": deckId])
        XCTAssertEqual(try arrayData(detail, key: "rows").count, 1)

        let started = try await call(engine, [
            "action": "quizStart",
            "deckId": deckId,
            "quizMode": "typing",
            "quizDirection": "native",
            "maxQuestions": 1,
            "includeNew": true,
            "practiceMode": true,
        ])
        XCTAssertNotNil(try dataObject(started)["question"] as? [String: Any])

        let inferred = try await call(engine, ["action": "quizTypedGrade", "answer": "house"])
        XCTAssertEqual(try dataObject(inferred)["grade"] as? Int, Grade.good.rawValue)

        let graded = try await call(engine, ["action": "quizGrade", "grade": Grade.good.rawValue])
        XCTAssertEqual(try dataObject(graded)["completed"] as? Bool, true)
        let progress = try XCTUnwrap(try dataObject(graded)["progress"] as? [String: Any])
        XCTAssertEqual(progress["answered"] as? Int, 1)
    }

    func testJSONBoundaryExportsImportsAndReturnsStructuredFailures() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let engine = DingerBridgeEngine(database: database)
        let deck = try await call(engine, ["action": "createDeck", "name": "Backup me"])
        let deckId = try XCTUnwrap(try dataObject(deck)["id"] as? Int)

        let exported = try await call(engine, ["action": "exportDeck", "deckId": deckId])
        let base64 = try XCTUnwrap(try dataObject(exported)["base64"] as? String)
        XCTAssertFalse(try XCTUnwrap(Data(base64Encoded: base64)).isEmpty)

        _ = try await call(engine, ["action": "deleteDeck", "deckId": deckId])
        let imported = try await call(engine, ["action": "importDecks", "base64": base64])
        XCTAssertEqual(try dataArray(imported).count, 1)

        let failure = try await call(engine, ["action": "notAnAction"])
        XCTAssertEqual(failure["ok"] as? Bool, false)
        XCTAssertTrue((failure["error"] as? String)?.contains("Unknown bridge action") == true)
    }

    private func call(_ engine: DingerBridgeEngine, _ request: [String: Any]) async throws -> [String: Any] {
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let response = await engine.call(String(decoding: requestData, as: UTF8.self))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
            "Invalid bridge response: \(response)"
        )
    }

    private func dataObject(_ response: [String: Any]) throws -> [String: Any] {
        XCTAssertEqual(response["ok"] as? Bool, true, response["error"] as? String ?? "")
        return try XCTUnwrap(response["data"] as? [String: Any])
    }

    private func dataArray(_ response: [String: Any]) throws -> [Any] {
        XCTAssertEqual(response["ok"] as? Bool, true, response["error"] as? String ?? "")
        return try XCTUnwrap(response["data"] as? [Any])
    }

    private func arrayData(_ response: [String: Any], key: String) throws -> [Any] {
        try XCTUnwrap(dataObject(response)[key] as? [Any])
    }
}
