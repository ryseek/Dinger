import Foundation
import GRDB

public nonisolated struct Deck: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var name: String
    public var sourceLang: String
    public var targetLang: String
    public var createdAt: Date

    public static let databaseTableName = "deck"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
        case createdAt = "created_at"
    }

    public init(id: Int64? = nil,
                name: String,
                sourceLang: String,
                targetLang: String,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var languagePair: LanguagePair {
        LanguagePair(source: sourceLang, target: targetLang)
    }
}
