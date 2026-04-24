import Foundation
import GRDB

public nonisolated enum CardDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case sourceToTarget = "s2t"
    case targetToSource = "t2s"

    public var displayLabel: String {
        switch self {
        case .sourceToTarget: return "source → target"
        case .targetToSource: return "target → source"
        }
    }
}

/// A saved dictionary sense, ready to be reviewed. front/back term IDs
/// are denormalized so the quiz can render a card without re-querying
/// through sense → term when it just needs one surface form; full
/// synonym lists are still fetched via `senseId` when needed.
public nonisolated struct Card: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var deckId: Int64
    public var senseId: Int64
    public var frontTermId: Int64
    public var backTermId: Int64
    public var direction: CardDirection
    public var createdAt: Date
    public var suspended: Bool

    public static let databaseTableName = "card"

    enum CodingKeys: String, CodingKey {
        case id
        case deckId = "deck_id"
        case senseId = "sense_id"
        case frontTermId = "front_term_id"
        case backTermId = "back_term_id"
        case direction
        case createdAt = "created_at"
        case suspended
    }

    public init(id: Int64? = nil,
                deckId: Int64,
                senseId: Int64,
                frontTermId: Int64,
                backTermId: Int64,
                direction: CardDirection,
                createdAt: Date = Date(),
                suspended: Bool = false) {
        self.id = id
        self.deckId = deckId
        self.senseId = senseId
        self.frontTermId = frontTermId
        self.backTermId = backTermId
        self.direction = direction
        self.createdAt = createdAt
        self.suspended = suspended
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// SM-2 spaced-repetition state. One row per card.
public nonisolated struct CardSRS: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    public var cardId: Int64
    public var ease: Double
    public var intervalDays: Double
    public var repetitions: Int
    public var lapses: Int
    public var dueAt: Date
    public var lastReviewedAt: Date?

    public static let databaseTableName = "card_srs"

    public var id: Int64 { cardId }

    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case ease
        case intervalDays = "interval_days"
        case repetitions
        case lapses
        case dueAt = "due_at"
        case lastReviewedAt = "last_reviewed_at"
    }

    public init(cardId: Int64,
                ease: Double = 2.5,
                intervalDays: Double = 0,
                repetitions: Int = 0,
                lapses: Int = 0,
                dueAt: Date = Date(),
                lastReviewedAt: Date? = nil) {
        self.cardId = cardId
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
    }
}

public nonisolated struct ReviewLog: Codable, Identifiable, FetchableRecord, MutablePersistableRecord, Hashable, Sendable {
    public var id: Int64?
    public var cardId: Int64
    public var reviewedAt: Date
    public var grade: Int            // 0..3
    public var prevInterval: Double
    public var newInterval: Double
    public var prevEase: Double
    public var newEase: Double

    public static let databaseTableName = "review_log"

    enum CodingKeys: String, CodingKey {
        case id
        case cardId = "card_id"
        case reviewedAt = "reviewed_at"
        case grade
        case prevInterval = "prev_interval"
        case newInterval = "new_interval"
        case prevEase = "prev_ease"
        case newEase = "new_ease"
    }

    public init(id: Int64? = nil,
                cardId: Int64,
                reviewedAt: Date,
                grade: Int,
                prevInterval: Double,
                newInterval: Double,
                prevEase: Double,
                newEase: Double) {
        self.id = id
        self.cardId = cardId
        self.reviewedAt = reviewedAt
        self.grade = grade
        self.prevInterval = prevInterval
        self.newInterval = newInterval
        self.prevEase = prevEase
        self.newEase = newEase
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
