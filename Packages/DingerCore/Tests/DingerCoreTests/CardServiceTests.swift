import Foundation
import XCTest
@testable import DingerCore

final class CardServiceTests: XCTestCase {
    func testReplacingCardSensePreservesIdentityAndProgress() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        let original = try await TestDatabaseSupport.card("Haus", deck: deck, service: service, database: database)
        _ = try await service.grade(
            card: original,
            grade: .good,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await database.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO term (id, sense_id, language_id, surface, headword, normalized)
                VALUES (43, 2, 2, 'wood', 'wood', 'wood')
                """)
        }

        let replacementHit = try await TestDatabaseSupport.hit("Baum", database: database)
        let replacement = try await service.replaceCard(
            original,
            with: replacementHit,
            selectedSourceTermId: 3,
            selectedTargetTermId: 43
        ).card

        XCTAssertEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.senseId, replacementHit.senseId)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(DeckExportFile.self, from: try await service.exportDeck(deck))
        let exportedCard = try XCTUnwrap(export.cards.first)
        XCTAssertEqual(exportedCard.frontTerms.first?.headword, "Baum")
        XCTAssertEqual(exportedCard.backTerms.first?.headword, "wood")
        XCTAssertEqual(exportedCard.srs.repetitions, 1)
        XCTAssertEqual(exportedCard.reviewHistory.count, 1)
    }

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

    func testCombinedQueuesIncludeCardsFromEveryDeckWithGlobalLimits() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let firstDeck = try await service.createDeck(name: "First", pair: .deEN)
        let secondDeck = try await service.createDeck(name: "Second", pair: .deEN)
        let dueCard = try await TestDatabaseSupport.card("Haus", deck: firstDeck, service: service, database: database)
        let firstNew = try await TestDatabaseSupport.card("Baum", deck: firstDeck, service: service, database: database)
        let secondDue = try await TestDatabaseSupport.card("Katze", deck: secondDeck, service: service, database: database)
        let reviewedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await service.grade(card: dueCard, grade: .good, now: reviewedAt)
        _ = try await service.grade(card: secondDue, grade: .good, now: reviewedAt)

        let queue = try await service.reviewQueue(
            decks: [firstDeck, secondDeck],
            now: reviewedAt.addingTimeInterval(2 * 86_400),
            maxCards: 2,
            maxNew: 1
        )

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(Set(queue.map(\.deckId)), Set([try XCTUnwrap(firstDeck.id), try XCTUnwrap(secondDeck.id)]))

        let practice = try await service.practiceQueue(decks: [firstDeck, secondDeck], maxCards: 10)
        XCTAssertEqual(
            Set(practice.compactMap(\.id)),
            Set([dueCard.id, firstNew.id, secondDue.id].compactMap { $0 })
        )
    }

    func testDeckStatisticsSummarizeProgressAndHardestCards() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        let difficultCard = try await TestDatabaseSupport.card("Haus", deck: deck, service: service, database: database)
        let learnedCard = try await TestDatabaseSupport.card("Baum", deck: deck, service: service, database: database)
        let reviewedAt = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await service.grade(card: difficultCard, grade: .again, now: reviewedAt)
        _ = try await service.grade(card: difficultCard, grade: .again, now: reviewedAt.addingTimeInterval(60))
        _ = try await service.grade(card: learnedCard, grade: .good, now: reviewedAt)

        let statistics = try await StudyInsightsService(database: database).statistics(for: deck)

        XCTAssertEqual(statistics.totalCards, 2)
        XCTAssertEqual(statistics.reviewedCards, 2)
        XCTAssertEqual(statistics.reviewedFraction, 1)
        XCTAssertEqual(statistics.dueCards, 2)
        XCTAssertEqual(statistics.totalReviews, 3)
        XCTAssertEqual(statistics.totalRepetitions, 1)
        XCTAssertEqual(statistics.matureCards, 0)
        XCTAssertEqual(statistics.learningCards, 2)
        XCTAssertEqual(statistics.successfulReviews, 1)
        XCTAssertEqual(statistics.retentionRate, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(statistics.hardestCards.first?.id, difficultCard.id)
        XCTAssertEqual(statistics.hardestCards.first?.againCount, 2)
        XCTAssertEqual(statistics.hardestCards.first?.reviewCount, 2)
    }

    func testDeckListActivitySummarizesTodayAndStreak() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        let card = try await TestDatabaseSupport.card("Haus", deck: deck, service: service, database: database)
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))

        _ = try await service.grade(card: card, grade: .good, now: yesterday)
        _ = try await service.grade(card: card, grade: .again, now: now)
        let activity = try await StudyInsightsService(database: database).activity(now: now)

        XCTAssertEqual(activity.activity(on: now)?.reviewCount, 1)
        XCTAssertEqual(activity.activity(on: now)?.correctCount, 0)
        XCTAssertEqual(activity.activity(on: yesterday)?.reviewCount, 1)
        XCTAssertEqual(activity.currentStreak, 2)
        XCTAssertEqual(activity.activity(on: yesterday)?.words.first?.front, "Haus {n}")
        XCTAssertEqual(activity.activity(on: yesterday)?.words.first?.isNew, true)
        XCTAssertEqual(activity.activity(on: now)?.words.first?.isNew, false)
        XCTAssertEqual(activity.activity(on: yesterday)?.words.first?.failedReviewCount, 0)
        XCTAssertEqual(activity.activity(on: now)?.words.first?.failedReviewCount, 1)
    }
}
