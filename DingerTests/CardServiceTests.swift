import Foundation
import XCTest
@testable import Dinger

final class CardServiceTests: XCTestCase {
    func testGradingUpdatesSRSAndCreatesReviewHistory() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        let card = try await TestDatabaseSupport.card("Haus", deck: deck, service: service, database: database)
        let reviewDate = Date(timeIntervalSince1970: 1_700_000_000)

        let updated = try await service.grade(card: card, grade: .good, now: reviewDate)
        XCTAssertEqual(updated.repetitions, 1)
        XCTAssertEqual(updated.intervalDays, 1)
        XCTAssertEqual(updated.lastReviewedAt, reviewDate)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(DeckExportFile.self, from: try await service.exportDeck(deck))
        let exportedCard = try XCTUnwrap(export.cards.first)
        XCTAssertEqual(exportedCard.reviewHistory.count, 1)
        XCTAssertEqual(exportedCard.reviewHistory.first?.grade, Grade.good.rawValue)
        XCTAssertEqual(exportedCard.srs.repetitions, 1)
    }

    func testReviewAndPracticeQueuesRespectDueNewAndSuspendedCards() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        let dueCard = try await TestDatabaseSupport.card("Haus", deck: deck, service: service, database: database)
        let newCard = try await TestDatabaseSupport.card("Baum", deck: deck, service: service, database: database)
        let suspendedCard = try await TestDatabaseSupport.card("Katze", deck: deck, service: service, database: database)

        let reviewedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await service.grade(card: dueCard, grade: .good, now: reviewedAt)
        _ = try await service.grade(card: suspendedCard, grade: .good, now: reviewedAt)
        try await service.suspend(card: suspendedCard, true)

        let afterDueDate = reviewedAt.addingTimeInterval(2 * 86_400)
        let reviewQueue = try await service.reviewQueue(
            deck: deck,
            now: afterDueDate,
            maxCards: 10,
            maxNew: 10
        )
        XCTAssertEqual(reviewQueue.map(\.id), [dueCard.id, newCard.id])

        let dueOnly = try await service.reviewQueue(
            deck: deck,
            now: afterDueDate,
            maxCards: 10,
            maxNew: 0
        )
        XCTAssertEqual(dueOnly.map(\.id), [dueCard.id])

        let practiceQueue = try await service.practiceQueue(deck: deck, maxCards: 10)
        XCTAssertEqual(Set(practiceQueue.compactMap(\.id)), Set([dueCard.id, newCard.id].compactMap { $0 }))
    }
}
