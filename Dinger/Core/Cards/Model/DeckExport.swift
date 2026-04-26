import Foundation

public nonisolated enum DeckExportFormat {
    public static let current = "dinger.deck.v1"
}

public nonisolated struct DeckExportFile: Codable, Hashable, Sendable {
    public var format: String
    public var exportedAt: Date
    public var deck: ExportedDeck
    public var cards: [ExportedCard]

    public init(format: String = DeckExportFormat.current,
                exportedAt: Date = Date(),
                deck: ExportedDeck,
                cards: [ExportedCard]) {
        self.format = format
        self.exportedAt = exportedAt
        self.deck = deck
        self.cards = cards
    }
}

public nonisolated struct ExportedDeck: Codable, Hashable, Sendable {
    public var name: String
    public var sourceLang: String
    public var targetLang: String

    public init(name: String, sourceLang: String, targetLang: String) {
        self.name = name
        self.sourceLang = sourceLang
        self.targetLang = targetLang
    }
}

public nonisolated struct ExportedCard: Codable, Hashable, Sendable {
    public var senseKey: ExportedSenseKey
    public var direction: CardDirection
    public var frontTerms: [ExportedTerm]
    public var backTerms: [ExportedTerm]
    public var suspended: Bool
    public var createdAt: Date

    public init(senseKey: ExportedSenseKey,
                direction: CardDirection,
                frontTerms: [ExportedTerm],
                backTerms: [ExportedTerm],
                suspended: Bool,
                createdAt: Date) {
        self.senseKey = senseKey
        self.direction = direction
        self.frontTerms = frontTerms
        self.backTerms = backTerms
        self.suspended = suspended
        self.createdAt = createdAt
    }
}

public nonisolated struct ExportedSenseKey: Codable, Hashable, Sendable {
    public var sourceLang: String
    public var targetLang: String
    public var entryRaw: String
    public var sensePosition: Int

    public init(sourceLang: String,
                targetLang: String,
                entryRaw: String,
                sensePosition: Int) {
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.entryRaw = entryRaw
        self.sensePosition = sensePosition
    }
}

public nonisolated struct ExportedTerm: Codable, Hashable, Sendable {
    public var language: String
    public var surface: String
    public var headword: String
    public var normalized: String
    public var pos: String?
    public var gender: String?

    public init(language: String,
                surface: String,
                headword: String,
                normalized: String,
                pos: String?,
                gender: String?) {
        self.language = language
        self.surface = surface
        self.headword = headword
        self.normalized = normalized
        self.pos = pos
        self.gender = gender
    }
}
