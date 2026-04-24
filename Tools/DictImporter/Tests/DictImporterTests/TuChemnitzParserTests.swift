import XCTest
@testable import DictImporter

final class TuChemnitzParserTests: XCTestCase {

    let parser = TuChemnitzParser()

    func testSkipsCommentsAndEmpty() {
        XCTAssertNil(parser.parse(line: "# Version: devel"))
        XCTAssertNil(parser.parse(line: ""))
        XCTAssertNil(parser.parse(line: "   "))
    }

    func testSingleGroup() {
        let entry = parser.parse(line: "Abbau {m} :: breakdown")
        XCTAssertEqual(entry?.senses.count, 1)
        let sense = entry!.senses[0]
        XCTAssertEqual(sense.sourceTerms.count, 1)
        XCTAssertEqual(sense.sourceTerms[0].headword, "Abbau")
        XCTAssertEqual(sense.sourceTerms[0].gender, "m")
        XCTAssertEqual(sense.targetTerms[0].headword, "breakdown")
    }

    func testMultipleSynonyms() {
        let line = "Abbau {m}; Abbauen {n}; Demontage {f}; Zerlegen {n} :: dismantlement; dismantling"
        let entry = parser.parse(line: line)
        XCTAssertEqual(entry?.senses.count, 1)
        let sense = entry!.senses[0]
        XCTAssertEqual(sense.sourceTerms.map(\.headword), ["Abbau", "Abbauen", "Demontage", "Zerlegen"])
        XCTAssertEqual(sense.sourceTerms.map(\.gender), ["m", "n", "f", "n"])
        XCTAssertEqual(sense.targetTerms.map(\.headword), ["dismantlement", "dismantling"])
    }

    func testDomainTagsAreSenseLevel() {
        let line = "Aalmolche {pl}; Fischmolche {pl} (Amphiuma) (zoologische Gattung) [zool.] <Aalmolch> :: amphiuma salamanders; amphiumas (zoological genus)"
        let entry = parser.parse(line: line)
        let sense = entry!.senses[0]
        XCTAssertEqual(sense.domain, ["zool."])
        XCTAssertNotNil(sense.context)
        XCTAssertTrue(sense.context!.contains("Amphiuma"))
        XCTAssertEqual(sense.sourceTerms[0].headword, "Aalmolche")
        XCTAssertEqual(sense.sourceTerms[0].altSpellings, []) // angle bracket is on second term
        XCTAssertEqual(sense.sourceTerms[1].altSpellings, ["Aalmolch"])
    }

    func testMultipleGroupsAlign() {
        let line = "Aal {m} | Aale {pl} :: eel | eels"
        let entry = parser.parse(line: line)
        XCTAssertEqual(entry?.senses.count, 2)
        XCTAssertEqual(entry?.senses[0].sourceTerms.first?.headword, "Aal")
        XCTAssertEqual(entry?.senses[0].targetTerms.first?.headword, "eel")
        XCTAssertEqual(entry?.senses[1].sourceTerms.first?.headword, "Aale")
        XCTAssertEqual(entry?.senses[1].targetTerms.first?.headword, "eels")
    }

    func testMismatchedGroupCount() {
        // Source has 2 groups, target has 3 — shouldn't crash.
        let line = "foo | bar :: alpha | beta | gamma"
        let entry = parser.parse(line: line)
        XCTAssertEqual(entry?.senses.count, 3)
        XCTAssertEqual(entry?.senses[2].sourceTerms.count, 0)
        XCTAssertEqual(entry?.senses[2].targetTerms.first?.headword, "gamma")
    }

    func testNormalizedFoldsUmlauts() {
        let entry = parser.parse(line: "Abänderung {f} :: amendment")
        let t = entry!.senses[0].sourceTerms[0]
        XCTAssertEqual(t.headword, "Abänderung")
        XCTAssertEqual(t.normalized, "abaenderung")
    }

    func testPosExtraction() {
        let entry = parser.parse(line: "Aas fressen {vi} :: to scavenge")
        XCTAssertEqual(entry!.senses[0].sourceTerms[0].pos, "vi")
    }

    func testBracketedPipeDoesNotSplitGroups() {
        // A '|' inside brackets should NOT split groups.
        let line = "foo [x|y] :: bar"
        let entry = parser.parse(line: line)
        XCTAssertEqual(entry?.senses.count, 1)
        XCTAssertEqual(entry?.senses[0].domain.contains("x|y"), true)
    }
}

final class TextNormalizerTests: XCTestCase {
    func testUmlautFold() {
        XCTAssertEqual(TextNormalizer.normalize("Abänderung"), "abaenderung")
        XCTAssertEqual(TextNormalizer.normalize("Mädchen"), "maedchen")
        XCTAssertEqual(TextNormalizer.normalize("Straße"), "strasse")
        XCTAssertEqual(TextNormalizer.normalize("Öl"), "oel")
        XCTAssertEqual(TextNormalizer.normalize("über"), "ueber")
    }

    func testDiacriticFold() {
        XCTAssertEqual(TextNormalizer.normalize("café"), "cafe")
        XCTAssertEqual(TextNormalizer.normalize("naïve"), "naive")
    }

    func testStripMarkup() {
        XCTAssertEqual(TextNormalizer.stripMarkup("Abbau {m}"), "Abbau")
        XCTAssertEqual(TextNormalizer.stripMarkup("eel (on a menu) [cook.]"), "eel")
        XCTAssertEqual(TextNormalizer.stripMarkup("Aalmolch <Aalm>"), "Aalmolch")
    }

    func testCollapseWhitespace() {
        XCTAssertEqual(TextNormalizer.normalize("  multiple   spaces  "), "multiple spaces")
    }
}
