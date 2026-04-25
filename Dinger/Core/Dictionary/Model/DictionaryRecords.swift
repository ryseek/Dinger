import Foundation
import GRDB

// MARK: - Language

public nonisolated struct Language: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var code: String

    public static let databaseTableName = "language"

    public init(id: Int64? = nil, code: String) {
        self.id = id
        self.code = code
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Dictionary

public nonisolated struct DictionaryRecord: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var sourceLangId: Int64
    public var targetLangId: Int64
    public var version: String
    public var name: String

    public static let databaseTableName = "dictionary"

    enum CodingKeys: String, CodingKey {
        case id
        case sourceLangId = "source_lang_id"
        case targetLangId = "target_lang_id"
        case version
        case name
    }

    public init(id: Int64? = nil, sourceLangId: Int64, targetLangId: Int64, version: String, name: String) {
        self.id = id
        self.sourceLangId = sourceLangId
        self.targetLangId = targetLangId
        self.version = version
        self.name = name
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Entry

public nonisolated struct Entry: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var dictionaryId: Int64
    public var raw: String

    public static let databaseTableName = "entry"

    enum CodingKeys: String, CodingKey {
        case id
        case dictionaryId = "dictionary_id"
        case raw
    }

    public init(id: Int64? = nil, dictionaryId: Int64, raw: String) {
        self.id = id
        self.dictionaryId = dictionaryId
        self.raw = raw
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Sense

public nonisolated struct Sense: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var entryId: Int64
    public var position: Int
    public var domain: String?   // semicolon-joined tags, e.g. "med.;zool."
    public var context: String?  // merged parenthetical disambiguation

    public static let databaseTableName = "sense"

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case position
        case domain
        case context
    }

    public init(id: Int64? = nil, entryId: Int64, position: Int, domain: String? = nil, context: String? = nil) {
        self.id = id
        self.entryId = entryId
        self.position = position
        self.domain = domain
        self.context = context
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var domainTags: [String] {
        guard let d = domain, !d.isEmpty else { return [] }
        return d.split(separator: ";").map { String($0) }
    }
}

// MARK: - Term

public nonisolated struct Term: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var senseId: Int64
    public var languageId: Int64
    public var surface: String       // as-rendered, e.g. "Abbau {m}"
    public var headword: String      // stripped of markers, e.g. "Abbau"
    public var normalized: String    // normalized search key
    public var pos: String?          // n / v / vt / vi / adj / adv …
    public var gender: String?       // m / f / n / pl

    public static let databaseTableName = "term"

    enum CodingKeys: String, CodingKey {
        case id
        case senseId = "sense_id"
        case languageId = "language_id"
        case surface
        case headword
        case normalized
        case pos
        case gender
    }

    public init(id: Int64? = nil,
                senseId: Int64,
                languageId: Int64,
                surface: String,
                headword: String,
                normalized: String,
                pos: String? = nil,
                gender: String? = nil) {
        self.id = id
        self.senseId = senseId
        self.languageId = languageId
        self.surface = surface
        self.headword = headword
        self.normalized = normalized
        self.pos = pos
        self.gender = gender
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Aggregate display types (NOT tables)

public nonisolated struct TermDisplay: Hashable, Sendable {
    public let termId: Int64
    public let surface: String
    public let headword: String
    public let pos: String?
    public let gender: String?
    public let languageCode: String

    public init(termId: Int64, surface: String, headword: String, pos: String?, gender: String?, languageCode: String) {
        self.termId = termId
        self.surface = surface
        self.headword = headword
        self.pos = pos
        self.gender = gender
        self.languageCode = languageCode
    }
}

/// One search result = one sense with its terms on both sides, plus
/// which term actually matched the query. Everything a card or detail
/// view needs is embedded.
public nonisolated struct SenseHit: Identifiable, Hashable, Sendable {
    public var id: Int64 { senseId }
    public let senseId: Int64
    public let entryId: Int64
    public let matchedTermId: Int64
    public let matchedLanguageCode: String
    public let sourceTerms: [TermDisplay]
    public let targetTerms: [TermDisplay]
    public let domain: [String]
    public let context: String?
    public let matchRank: Int  // 0 = exact, higher = worse

    public init(senseId: Int64,
                entryId: Int64,
                matchedTermId: Int64,
                matchedLanguageCode: String,
                sourceTerms: [TermDisplay],
                targetTerms: [TermDisplay],
                domain: [String],
                context: String?,
                matchRank: Int) {
        self.senseId = senseId
        self.entryId = entryId
        self.matchedTermId = matchedTermId
        self.matchedLanguageCode = matchedLanguageCode
        self.sourceTerms = sourceTerms
        self.targetTerms = targetTerms
        self.domain = domain
        self.context = context
        self.matchRank = matchRank
    }
}

public nonisolated struct ExampleSentence: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let germanTatoebaId: Int64
    public let englishTatoebaId: Int64
    public let germanText: String
    public let englishText: String

    public init(id: Int64,
                germanTatoebaId: Int64,
                englishTatoebaId: Int64,
                germanText: String,
                englishText: String) {
        self.id = id
        self.germanTatoebaId = germanTatoebaId
        self.englishTatoebaId = englishTatoebaId
        self.germanText = germanText
        self.englishText = englishText
    }

    public func text(for languageCode: String) -> String {
        languageCode == "de" ? germanText : englishText
    }
}
