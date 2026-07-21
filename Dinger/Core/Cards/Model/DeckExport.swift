import Foundation

public nonisolated enum DeckExportFormat {
    public static let current = "dinger.deck.v3"
    public static let supported: Set<String> = ["dinger.deck.v2", current]
}

public nonisolated enum AllDecksExportFormat {
    public static let current = "dinger.backup.v1"
}

public nonisolated struct AllDecksExportFile: Codable, Hashable, Sendable {
    public var format: String
    public var exportedAt: Date
    public var decks: [DeckExportFile]

    public init(format: String = AllDecksExportFormat.current,
                exportedAt: Date = Date(),
                decks: [DeckExportFile]) {
        self.format = format
        self.exportedAt = exportedAt
        self.decks = decks
    }
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
    public var frontTextOverride: String?
    public var backTextOverride: String?
    public var suspended: Bool
    public var createdAt: Date
    public var srs: ExportedCardSRS
    public var reviewHistory: [ExportedReview]

    public init(senseKey: ExportedSenseKey,
                direction: CardDirection,
                frontTerms: [ExportedTerm],
                backTerms: [ExportedTerm],
                frontTextOverride: String? = nil,
                backTextOverride: String? = nil,
                suspended: Bool,
                createdAt: Date,
                srs: ExportedCardSRS,
                reviewHistory: [ExportedReview]) {
        self.senseKey = senseKey
        self.direction = direction
        self.frontTerms = frontTerms
        self.backTerms = backTerms
        self.frontTextOverride = Card.cleanedTextOverride(frontTextOverride)
        self.backTextOverride = Card.cleanedTextOverride(backTextOverride)
        self.suspended = suspended
        self.createdAt = createdAt
        self.srs = srs
        self.reviewHistory = reviewHistory
    }
}

public nonisolated struct ExportedCardSRS: Codable, Hashable, Sendable {
    public var ease: Double
    public var intervalDays: Double
    public var repetitions: Int
    public var lapses: Int
    public var dueAt: Date
    public var lastReviewedAt: Date?

    public init(ease: Double,
                intervalDays: Double,
                repetitions: Int,
                lapses: Int,
                dueAt: Date,
                lastReviewedAt: Date?) {
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
    }
}

public nonisolated struct ExportedReview: Codable, Hashable, Sendable {
    public var reviewedAt: Date
    public var grade: Int
    public var prevInterval: Double
    public var newInterval: Double
    public var prevEase: Double
    public var newEase: Double

    public init(reviewedAt: Date,
                grade: Int,
                prevInterval: Double,
                newInterval: Double,
                prevEase: Double,
                newEase: Double) {
        self.reviewedAt = reviewedAt
        self.grade = grade
        self.prevInterval = prevInterval
        self.newInterval = newInterval
        self.prevEase = prevEase
        self.newEase = newEase
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
