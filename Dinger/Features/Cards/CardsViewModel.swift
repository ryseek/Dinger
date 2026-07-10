import Foundation
import Observation
import GRDB

@Observable
@MainActor
public final class DeckListViewModel {
    public var decks: [Deck] = []
    public var activity: StudyActivitySummary = .empty
    public var error: String?
    public var isAddingDeck = false
    public var deckAddProgress: Double?
    public var deckAddStatus: String?
    private let service: CardService
    private let database: AppDatabase
    private let pair: LanguagePair

    public init(service: CardService, database: AppDatabase, pair: LanguagePair) {
        self.service = service
        self.database = database
        self.pair = pair
    }

    public func reload() async {
        do {
            _ = try await service.ensureDefaultDeck(for: pair) // guarantee a default deck exists
            async let loadedDecks = service.allDecks()
            async let loadedActivity = fetchActivity()
            (decks, activity) = try await (loadedDecks, loadedActivity)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func reloadActivity() async {
        do {
            activity = try await fetchActivity()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func createDeck(name: String) async {
        beginDeckAdd(status: "Creating deck...", progress: nil)
        defer { finishDeckAdd() }
        do {
            _ = try await service.createDeck(name: name, pair: pair)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func rename(_ deck: Deck, to name: String) async {
        do {
            _ = try await service.renameDeck(deck, to: name)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func export(_ deck: Deck) async -> Data? {
        do {
            let data = try await service.exportDeck(deck)
            error = nil
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func exportAllDecks() async -> Data? {
        do {
            let data = try await service.exportAllDecks()
            error = nil
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func importDeck(data: Data) async {
        beginDeckAdd(status: "Importing deck or backup...", progress: 0)
        defer { finishDeckAdd() }
        do {
            _ = try await service.importDecks(from: data) { [weak self] progress in
                Task { @MainActor in
                    self?.deckAddProgress = progress
                }
            }
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func setError(_ message: String) {
        error = message
    }

    public func delete(_ deck: Deck) async {
        do {
            try await service.deleteDeck(deck)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func beginDeckAdd(status: String, progress: Double?) {
        isAddingDeck = true
        deckAddStatus = status
        deckAddProgress = progress
        error = nil
    }

    private func finishDeckAdd() {
        isAddingDeck = false
        deckAddStatus = nil
        deckAddProgress = nil
    }

    private func fetchActivity(now: Date = Date()) async throws -> StudyActivitySummary {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -370, to: today) ?? .distantPast

        return try await database.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT reviewed_at, grade
                  FROM review_log
                 WHERE reviewed_at >= ?
                 ORDER BY reviewed_at ASC
                """, arguments: [cutoff])

            var counts: [Date: (reviews: Int, correct: Int)] = [:]
            for row in rows {
                let reviewedAt: Date = row["reviewed_at"]
                let day = calendar.startOfDay(for: reviewedAt)
                var count = counts[day] ?? (0, 0)
                count.reviews += 1
                if (row["grade"] as Int? ?? Grade.again.rawValue) != Grade.again.rawValue {
                    count.correct += 1
                }
                counts[day] = count
            }

            let days = counts.map { day, count in
                StudyDay(date: day, reviewCount: count.reviews, correctCount: count.correct)
            }.sorted { $0.date < $1.date }

            var streak = 0
            var cursor = counts[today] == nil
                ? (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
                : today
            while let count = counts[cursor], count.reviews > 0 {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            }

            return StudyActivitySummary(days: days, currentStreak: streak)
        }
    }
}

public struct StudyDay: Identifiable, Hashable, Sendable {
    public let date: Date
    public let reviewCount: Int
    public let correctCount: Int

    public var id: Date { date }

    public var retention: Double {
        guard reviewCount > 0 else { return 0 }
        return Double(correctCount) / Double(reviewCount)
    }
}

public struct StudyActivitySummary: Hashable, Sendable {
    public let days: [StudyDay]
    public let currentStreak: Int

    public static let empty = StudyActivitySummary(days: [], currentStreak: 0)

    public func activity(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> StudyDay? {
        let target = calendar.startOfDay(for: date)
        return days.first { calendar.isDate($0.date, inSameDayAs: target) }
    }
}

public struct CardRow: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let card: Card
    public let frontSurfaces: [String]
    public let backSurfaces: [String]
    public let dueAt: Date?
    public let repetitions: Int
    public let suspended: Bool

    public var frontSurface: String {
        frontSurfaces.first ?? "?"
    }

    public var backSurface: String {
        backSurfaces.first ?? "?"
    }
}

public struct DifficultCard: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let front: String
    public let back: String
    public let againCount: Int
    public let reviewCount: Int
}

public struct DeckStatistics: Hashable, Sendable {
    public let totalCards: Int
    public let reviewedCards: Int
    public let dueCards: Int
    public let totalReviews: Int
    public let totalRepetitions: Int
    public let matureCards: Int
    public let learningCards: Int
    public let reviewsThisWeek: Int
    public let dueTomorrow: Int
    public let successfulReviews: Int
    public let hardestCards: [DifficultCard]

    public static let empty = DeckStatistics(
        totalCards: 0,
        reviewedCards: 0,
        dueCards: 0,
        totalReviews: 0,
        totalRepetitions: 0,
        matureCards: 0,
        learningCards: 0,
        reviewsThisWeek: 0,
        dueTomorrow: 0,
        successfulReviews: 0,
        hardestCards: []
    )

    public var reviewedFraction: Double {
        guard totalCards > 0 else { return 0 }
        return Double(reviewedCards) / Double(totalCards)
    }

    public var retentionRate: Double {
        guard totalReviews > 0 else { return 0 }
        return Double(successfulReviews) / Double(totalReviews)
    }
}

@Observable
@MainActor
public final class DeckDetailViewModel {
    public var rows: [CardRow] = []
    public var statistics: DeckStatistics = .empty
    public var error: String?
    public private(set) var deck: Deck

    private let service: CardService
    private let database: AppDatabase

    public init(service: CardService, database: AppDatabase, deck: Deck) {
        self.service = service
        self.database = database
        self.deck = deck
    }

    public func reload() async {
        do {
            async let loadedRows = fetchRows()
            async let loadedStatistics = fetchStatistics()
            (rows, statistics) = try await (loadedRows, loadedStatistics)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func suspend(_ row: CardRow) async {
        do {
            try await service.suspend(card: row.card, !row.suspended)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func delete(_ row: CardRow) async {
        do {
            try await service.delete(card: row.card)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func renameDeck(to name: String) async {
        do {
            deck = try await service.renameDeck(deck, to: name)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func exportDeck() async -> Data? {
        do {
            let data = try await service.exportDeck(deck)
            error = nil
            return data
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    public func setError(_ message: String) {
        error = message
    }

    /// Fetch decorated rows off the writer queue.
    private func fetchRows() async throws -> [CardRow] {
        guard let deckId = deck.id else { return [] }
        return try await database.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.*,
                       tf.surface AS front_surface,
                       tb.surface AS back_surface,
                       s.due_at   AS due_at,
                       s.repetitions AS repetitions
                  FROM card c
                  LEFT JOIN term tf ON tf.id = c.front_term_id
                  LEFT JOIN term tb ON tb.id = c.back_term_id
                  LEFT JOIN card_srs s ON s.card_id = c.id
                 WHERE c.deck_id = ?
                 ORDER BY c.created_at DESC
                """, arguments: [deckId])
            return try rows.map { row -> CardRow in
                let card = Card(
                    id: row["id"],
                    deckId: row["deck_id"],
                    senseId: row["sense_id"],
                    frontTermId: row["front_term_id"],
                    backTermId: row["back_term_id"],
                    frontTermIds: Card.decodeTermIds(row["front_term_ids"] ?? ""),
                    backTermIds: Card.decodeTermIds(row["back_term_ids"] ?? ""),
                    direction: CardDirection(rawValue: row["direction"]) ?? .sourceToTarget,
                    createdAt: row["created_at"],
                    suspended: (row["suspended"] as Int? ?? 0) != 0
                )
                let frontSurfaces = try Self.termSurfaces(db: db, termIds: card.frontTermIds)
                let backSurfaces = try Self.termSurfaces(db: db, termIds: card.backTermIds)
                return CardRow(
                    id: card.id ?? 0,
                    card: card,
                    frontSurfaces: frontSurfaces.isEmpty ? [row["front_surface"] ?? "?"] : frontSurfaces,
                    backSurfaces: backSurfaces.isEmpty ? [row["back_surface"] ?? "?"] : backSurfaces,
                    dueAt: row["due_at"],
                    repetitions: row["repetitions"] ?? 0,
                    suspended: card.suspended
                )
            }
        }
    }

    private func fetchStatistics(now: Date = Date()) async throws -> DeckStatistics {
        guard let deckId = deck.id else { return .empty }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? .distantPast
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) ?? now
        return try await database.dbWriter.read { db in
            let totals = try Row.fetchOne(db, sql: """
                SELECT COUNT(c.id) AS total_cards,
                       COALESCE(SUM(CASE WHEN s.last_reviewed_at IS NOT NULL THEN 1 ELSE 0 END), 0) AS reviewed_cards,
                       COALESCE(SUM(CASE
                           WHEN c.suspended = 0
                            AND s.last_reviewed_at IS NOT NULL
                            AND s.due_at <= ? THEN 1 ELSE 0 END), 0) AS due_cards,
                       COALESCE(SUM(s.repetitions), 0) AS total_repetitions,
                       COALESCE(SUM(CASE
                           WHEN s.last_reviewed_at IS NOT NULL
                            AND s.interval_days >= 21 THEN 1 ELSE 0 END), 0) AS mature_cards,
                       COALESCE(SUM(CASE
                           WHEN s.last_reviewed_at IS NOT NULL
                            AND s.interval_days < 21 THEN 1 ELSE 0 END), 0) AS learning_cards,
                       COALESCE(SUM(CASE
                           WHEN c.suspended = 0
                            AND s.last_reviewed_at IS NOT NULL
                            AND s.due_at >= ? AND s.due_at < ? THEN 1 ELSE 0 END), 0) AS due_tomorrow,
                       (SELECT COUNT(*)
                          FROM review_log r
                          JOIN card reviewed_card ON reviewed_card.id = r.card_id
                         WHERE reviewed_card.deck_id = ?) AS total_reviews,
                       (SELECT COUNT(*)
                          FROM review_log r
                          JOIN card reviewed_card ON reviewed_card.id = r.card_id
                         WHERE reviewed_card.deck_id = ?
                           AND r.reviewed_at >= ?) AS reviews_this_week,
                       (SELECT COUNT(*)
                          FROM review_log r
                          JOIN card reviewed_card ON reviewed_card.id = r.card_id
                         WHERE reviewed_card.deck_id = ?
                           AND r.grade != ?) AS successful_reviews
                  FROM card c
                  LEFT JOIN card_srs s ON s.card_id = c.id
                 WHERE c.deck_id = ?
                """, arguments: [now, tomorrow, dayAfterTomorrow, deckId, deckId, weekAgo, deckId, Grade.again.rawValue, deckId])

            let hardestRows = try Row.fetchAll(db, sql: """
                SELECT c.id,
                       COALESCE(tf.surface, '?') AS front,
                       COALESCE(tb.surface, '?') AS back,
                       COUNT(r.id) AS review_count,
                       SUM(CASE WHEN r.grade = ? THEN 1 ELSE 0 END) AS again_count
                  FROM card c
                  LEFT JOIN term tf ON tf.id = c.front_term_id
                  LEFT JOIN term tb ON tb.id = c.back_term_id
                  JOIN review_log r ON r.card_id = c.id
                 WHERE c.deck_id = ?
                 GROUP BY c.id
                HAVING SUM(CASE WHEN r.grade = ? THEN 1 ELSE 0 END) > 0
                 ORDER BY again_count DESC, review_count DESC, c.id ASC
                 LIMIT 3
                """, arguments: [Grade.again.rawValue, deckId, Grade.again.rawValue])

            return DeckStatistics(
                totalCards: totals?["total_cards"] ?? 0,
                reviewedCards: totals?["reviewed_cards"] ?? 0,
                dueCards: totals?["due_cards"] ?? 0,
                totalReviews: totals?["total_reviews"] ?? 0,
                totalRepetitions: totals?["total_repetitions"] ?? 0,
                matureCards: totals?["mature_cards"] ?? 0,
                learningCards: totals?["learning_cards"] ?? 0,
                reviewsThisWeek: totals?["reviews_this_week"] ?? 0,
                dueTomorrow: totals?["due_tomorrow"] ?? 0,
                successfulReviews: totals?["successful_reviews"] ?? 0,
                hardestCards: hardestRows.map {
                    DifficultCard(
                        id: $0["id"],
                        front: $0["front"],
                        back: $0["back"],
                        againCount: $0["again_count"],
                        reviewCount: $0["review_count"]
                    )
                }
            )
        }
    }

    private nonisolated static func termSurfaces(db: Database, termIds: [Int64]) throws -> [String] {
        guard !termIds.isEmpty else { return [] }
        let surfacesById = try termIds.reduce(into: [Int64: String]()) { result, termId in
            if let surface = try String.fetchOne(db, sql: "SELECT surface FROM term WHERE id = ?", arguments: [termId]) {
                result[termId] = surface
            }
        }
        return termIds.compactMap { surfacesById[$0] }
    }
}
