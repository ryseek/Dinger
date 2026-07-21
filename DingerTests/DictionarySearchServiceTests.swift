import XCTest
@testable import Dinger

final class DictionarySearchServiceTests: XCTestCase {
    func testNormalWordAndPhraseSearchesStillWork() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = DictionarySearchService(database: database)

        let wordResults = try await service.search("Haus")
        XCTAssertEqual(wordResults.first?.senseId, 1)

        let phraseResults = try await service.search("small house")
        XCTAssertTrue(phraseResults.isEmpty)
    }

    func testPunctuationQueryDoesNotThrowOrProduceBroadFTSMatches() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = DictionarySearchService(database: database)

        let results = try await service.search("C++")
        XCTAssertEqual(results.map(\.senseId), [4])
    }

    func testLikeMetacharactersAreTreatedLiterally() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = DictionarySearchService(database: database)

        let percentResults = try await service.search("%")
        let underscoreResults = try await service.search("_")
        let caretResults = try await service.search("^")
        let quoteResults = try await service.search("\"")
        XCTAssertTrue(percentResults.isEmpty)
        XCTAssertTrue(underscoreResults.isEmpty)
        XCTAssertTrue(caretResults.isEmpty)
        XCTAssertTrue(quoteResults.isEmpty)
    }

    func testAutoDirectionPrefersExactEnglishMatchOverGermanPrefix() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = DictionarySearchService(database: database)

        let results = try await service.search("car")

        XCTAssertEqual(results.first?.senseId, 8)
        XCTAssertEqual(results.first?.matchedLanguageCode, "en")
        XCTAssertEqual(results.first?.sourceTerms.first?.headword, "Auto")
        let carport = results.first { $0.senseId == 22 }
        XCTAssertEqual(carport?.matchedLanguageCode, "en")
        XCTAssertEqual(carport?.matchRank, 1, "English carport may remain as a lower-ranked prefix result")
    }

    func testExactMatchesPreferSimplerTranslationHeadword() async throws {
        let database = try await TestDatabaseSupport.makeDatabase()
        let service = DictionarySearchService(database: database)

        let exactCarResults = try await service.search("car")

        XCTAssertEqual(exactCarResults.filter { $0.matchRank == 0 }.map(\.senseId), [8, 23])
    }
}
