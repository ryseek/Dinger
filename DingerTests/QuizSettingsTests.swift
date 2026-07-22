import Foundation
import XCTest
@testable import Dinger

final class QuizSettingsTests: XCTestCase {
    func testActiveQuizShowsCurrentQuestionOutOfStableTotal() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        _ = try await TestDatabaseSupport.card("Haus", deck: deck, service: service, database: database)
        _ = try await TestDatabaseSupport.card("Baum", deck: deck, service: service, database: database)
        let session = QuizSession(
            decks: [deck],
            config: QuizConfig(mode: .flashcard, maxQuestions: 2, practiceMode: true),
            cardService: service,
            reader: database.dbWriter
        )
        let viewModel = QuizPlayViewModel(session: session)

        await viewModel.start()

        XCTAssertEqual(viewModel.progress.answered, 0)
        XCTAssertEqual(viewModel.progress.total, 2)
        XCTAssertEqual(viewModel.questionNumber, 1)
    }

    func testQuizStartSettingsAreRestored() async throws {
        let suiteName = "QuizSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)

        let first = QuizStartViewModel(service: service, defaults: defaults)
        first.selectedDeckId = 42
        first.mode = .typing
        first.direction = .mixed
        first.maxQuestions = 35
        first.includeNew = false
        first.showExamplesDuringQuestion = true
        first.practiceMode = true

        let restored = QuizStartViewModel(service: service, defaults: defaults)

        XCTAssertEqual(restored.selectedDeckId, 42)
        XCTAssertEqual(restored.mode, .typing)
        XCTAssertEqual(restored.direction, .mixed)
        XCTAssertEqual(restored.maxQuestions, 35)
        XCTAssertFalse(restored.includeNew)
        XCTAssertTrue(restored.showExamplesDuringQuestion)
        XCTAssertTrue(restored.practiceMode)
    }

    func testAllDecksSelectionIsRestored() async throws {
        let suiteName = "QuizSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)

        let first = QuizStartViewModel(service: service, defaults: defaults)
        first.selectedDeckId = 42
        first.selectedDeckId = nil

        let restored = QuizStartViewModel(service: service, defaults: defaults)
        XCTAssertNil(restored.selectedDeckId)
    }
}
