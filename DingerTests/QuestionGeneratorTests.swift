import XCTest
@testable import Dinger

final class QuestionGeneratorTests: XCTestCase {
    func testMultipleChoiceGeneratesEightUniqueChoices() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Study", pair: .deEN)
        let card = try await TestDatabaseSupport.card(
            "Haus",
            deck: deck,
            service: service,
            database: database
        )
        let generator = QuestionGenerator(reader: database.dbWriter, deck: deck)

        let question = try await generator.makeQuestion(for: card, mode: .multipleChoice)

        XCTAssertEqual(question.choices.count, 8)
        XCTAssertEqual(Set(question.choices.map(TextNormalizer.normalize)).count, 8)
        let correctIndex = try XCTUnwrap(question.correctIndex)
        XCTAssertTrue(question.choices.indices.contains(correctIndex))
        XCTAssertTrue(
            question.acceptableAnswers.contains(
                TextNormalizer.normalize(question.choices[correctIndex])
            )
        )
    }

    func testMultipleChoiceUsesSameCategoryCardsFromOtherDecks() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let quizDeck = try await service.createDeck(name: "Quiz", pair: .deEN)
        let otherDeck = try await service.createDeck(name: "Other", pair: .deEN)
        let questionCard = try await TestDatabaseSupport.card(
            "Haus",
            deck: quizDeck,
            service: service,
            database: database
        )
        _ = try await TestDatabaseSupport.card("Hund", deck: otherDeck, service: service, database: database)
        _ = try await TestDatabaseSupport.card("Buch", deck: otherDeck, service: service, database: database)

        let generator = QuestionGenerator(reader: database.dbWriter, deck: quizDeck)
        let question = try await generator.makeQuestion(for: questionCard, mode: .multipleChoice)
        let normalizedChoices = Set(question.choices.map(TextNormalizer.normalize))

        XCTAssertEqual(question.choices.count, 8)
        XCTAssertTrue(normalizedChoices.isSuperset(of: ["dog", "book"]))
        XCTAssertTrue(normalizedChoices.isDisjoint(with: ["run", "fast", "c++"]))
    }

    func testMultipleChoiceKeepsVerbDistractorsInVerbCategory() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Verbs", pair: .deEN)
        let questionCard = try await TestDatabaseSupport.card(
            "laufen",
            deck: deck,
            service: service,
            database: database
        )
        let generator = QuestionGenerator(reader: database.dbWriter, deck: deck)

        let question = try await generator.makeQuestion(for: questionCard, mode: .multipleChoice)
        let normalizedChoices = Set(question.choices.map(TextNormalizer.normalize))

        XCTAssertTrue(normalizedChoices.contains("walk"))
        XCTAssertTrue(normalizedChoices.isDisjoint(with: ["house", "tree", "cat", "fast", "c++"]))
    }

    func testMultipleChoiceExcludesAnotherValidTranslation() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = CardService(database: database)
        let deck = try await service.createDeck(name: "Confusions", pair: .deEN)
        let questionCard = try await TestDatabaseSupport.card(
            "wissen",
            deck: deck,
            service: service,
            database: database
        )
        let generator = QuestionGenerator(reader: database.dbWriter, deck: deck)

        let question = try await generator.makeQuestion(
            for: questionCard,
            mode: .multipleChoice,
            directionOverride: .targetToSource
        )
        let normalizedChoices = Set(question.choices.map(TextNormalizer.normalize))

        XCTAssertEqual(question.choices.count, 8)
        XCTAssertTrue(normalizedChoices.contains("wissen"))
        XCTAssertFalse(normalizedChoices.contains("kennen"))
        XCTAssertTrue(normalizedChoices.isDisjoint(with: ["haus", "schnell", "c++"]))
    }
}
