import Foundation
import XCTest
@testable import DingerCore

final class DeckBackupTests: XCTestCase {
    func testAllDecksBackupRoundTripPreservesProgressAndHistory() async throws {
        let sourceDatabase = try await TestDatabaseSupport.makeDatabase()
        let sourceService = CardService(database: sourceDatabase)
        let studiedDeck = try await sourceService.createDeck(name: "Studied", pair: .deEN)
        _ = try await sourceService.createDeck(name: "Empty", pair: .deEN)
        let card = try await TestDatabaseSupport.card(
            "Haus",
            deck: studiedDeck,
            service: sourceService,
            database: sourceDatabase
        )
        try await sourceService.suspend(card: card, true)

        let firstReview = Date(timeIntervalSince1970: 1_700_000_000)
        let secondReview = firstReview.addingTimeInterval(86_400)
        _ = try await sourceService.grade(card: card, grade: .good, now: firstReview)
        let expectedSRS = try await sourceService.grade(card: card, grade: .easy, now: secondReview)

        let backupData = try await sourceService.exportAllDecks()
        let exported = try decodeBackup(backupData)
        XCTAssertEqual(exported.decks.count, 2)
        let exportedCard = try XCTUnwrap(exported.decks.first { $0.deck.name == "Studied" }?.cards.first)
        XCTAssertEqual(exportedCard.srs.repetitions, expectedSRS.repetitions)
        XCTAssertEqual(exportedCard.srs.lapses, expectedSRS.lapses)
        XCTAssertEqual(exportedCard.reviewHistory.count, 2)

        let destinationDatabase = try await TestDatabaseSupport.makeDatabase()
        let destinationService = CardService(database: destinationDatabase)
        let importedDecks = try await destinationService.importDecks(from: backupData)
        XCTAssertEqual(importedDecks.map(\.name).sorted(), ["Empty", "Studied"])

        let importedStudiedDeck = try XCTUnwrap(importedDecks.first { $0.name == "Studied" })
        let importedCards = try await destinationService.cards(in: importedStudiedDeck)
        let importedCard = try XCTUnwrap(importedCards.first)
        let restoredSRS = try await destinationService.srs(for: importedCard)
        let importedSRS = try XCTUnwrap(restoredSRS)
        XCTAssertTrue(importedCard.suspended)
        XCTAssertEqual(importedSRS.ease, expectedSRS.ease)
        XCTAssertEqual(importedSRS.intervalDays, expectedSRS.intervalDays)
        XCTAssertEqual(importedSRS.repetitions, expectedSRS.repetitions)
        XCTAssertEqual(importedSRS.lapses, expectedSRS.lapses)
        XCTAssertEqual(importedSRS.dueAt, expectedSRS.dueAt)
        XCTAssertEqual(importedSRS.lastReviewedAt, expectedSRS.lastReviewedAt)

        let restoredBackup = try decodeBackup(try await destinationService.exportAllDecks())
        let restoredCard = try XCTUnwrap(restoredBackup.decks.first { $0.deck.name == "Studied" }?.cards.first)
        XCTAssertEqual(restoredCard.reviewHistory, exportedCard.reviewHistory)
    }

    func testMalformedBackupRollsBackEveryDeck() async throws {
        let sourceDatabase = try await TestDatabaseSupport.makeDatabase()
        let sourceService = CardService(database: sourceDatabase)
        let firstDeck = try await sourceService.createDeck(name: "First", pair: .deEN)
        let secondDeck = try await sourceService.createDeck(name: "Second", pair: .deEN)
        _ = try await TestDatabaseSupport.card("Haus", deck: firstDeck, service: sourceService, database: sourceDatabase)
        _ = try await TestDatabaseSupport.card("Baum", deck: secondDeck, service: sourceService, database: sourceDatabase)

        var backup = try decodeBackup(try await sourceService.exportAllDecks())
        backup.decks[1].cards[0].frontTerms[0].surface = "not in dictionary"
        let malformedData = try encodeBackup(backup)

        let destinationDatabase = try await TestDatabaseSupport.makeDatabase()
        let destinationService = CardService(database: destinationDatabase)
        do {
            _ = try await destinationService.importDecks(from: malformedData)
            XCTFail("Expected malformed backup import to fail")
        } catch {
            // Expected: the enclosing GRDB write transaction must roll back.
        }
        let remainingDecks = try await destinationService.allDecks()
        XCTAssertTrue(remainingDecks.isEmpty)
    }

    private func decodeBackup(_ data: Data) throws -> AllDecksExportFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AllDecksExportFile.self, from: data)
    }

    private func encodeBackup(_ backup: AllDecksExportFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }
}
