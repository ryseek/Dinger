import XCTest
@testable import DictImporter

final class TatoebaSentenceParserTests: XCTestCase {
    func testParsesValidSentencePair() {
        let pair = TatoebaSentenceParser.parse(line: "77\tLass uns etwas versuchen!\t1276\tLet's try something.")

        XCTAssertEqual(pair?.germanId, 77)
        XCTAssertEqual(pair?.germanText, "Lass uns etwas versuchen!")
        XCTAssertEqual(pair?.englishId, 1276)
        XCTAssertEqual(pair?.englishText, "Let's try something.")
    }

    func testRejectsBlankAndMalformedRows() {
        XCTAssertNil(TatoebaSentenceParser.parse(line: ""))
        XCTAssertNil(TatoebaSentenceParser.parse(line: "77\tNur Deutsch"))
        XCTAssertNil(TatoebaSentenceParser.parse(line: "abc\tHallo\t123\tHello."))
        XCTAssertNil(TatoebaSentenceParser.parse(line: "77\t\t123\tHello."))
    }

    func testNormalizerFoldsUmlautsForExamples() {
        XCTAssertEqual(TextNormalizer.normalize("Abänderung für Müßiggang"), "abaenderung fuer muessiggang")
    }
}
