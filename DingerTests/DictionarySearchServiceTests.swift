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
}
