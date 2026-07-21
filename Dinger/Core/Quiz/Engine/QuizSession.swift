import Foundation
import GRDB

/// Drives a single quiz run. UI-framework free so it's testable.
///
/// Usage pattern:
///   let session = QuizSession(...)
///   try await session.start()
///   while let q = try await session.nextQuestion() {
///       // present q, collect answer
///       let grade = session.gradeFromAnswer(..., for: q)
///       try await session.recordAnswer(q, grade: grade)
///   }
///   // session.progress holds final counts
public nonisolated final class QuizSession: @unchecked Sendable {

    public let decks: [Deck]
    public let config: QuizConfig
    private let cardService: CardService
    private let generators: [Int64: QuestionGenerator]

    private var queue: [Card] = []
    private var cardsById: [Int64: Card] = [:]
    private var state = State()

    private struct State {
        var answered = 0
        var correct = 0
        var perGrade = [Grade: Int]()
        var startedAt: Date = .distantPast
    }

    public init(decks: [Deck],
                config: QuizConfig,
                cardService: CardService,
                reader: any DatabaseReader) {
        self.decks = decks
        self.config = config
        self.cardService = cardService
        self.generators = Dictionary(uniqueKeysWithValues: decks.compactMap { deck in
            guard let deckId = deck.id else { return nil }
            return (deckId, QuestionGenerator(reader: reader, deck: deck))
        })
    }

    public var progress: QuizProgress {
        QuizProgress(
            answered: state.answered,
            total: queue.count + state.answered,
            correct: state.correct,
            again: state.perGrade[.again] ?? 0,
            hard:  state.perGrade[.hard]  ?? 0,
            good:  state.perGrade[.good]  ?? 0,
            easy:  state.perGrade[.easy]  ?? 0
        )
    }

    public func start() async throws {
        let cards: [Card]
        if config.practiceMode {
            // In practice we shuffle so repeat sessions don't always begin
            // with the same cards; ordering priorities are less important
            // when there's no "due" contract to honor.
            cards = try await cardService.practiceQueue(
                decks: decks,
                maxCards: config.maxQuestions
            ).shuffled()
        } else {
            let maxNew = config.includeNewCards ? config.maxQuestions : 0
            cards = try await cardService.reviewQueue(
                decks: decks,
                maxCards: config.maxQuestions,
                maxNew: maxNew
            )
        }
        queue = Array(cards.prefix(config.maxQuestions))
        cardsById = Dictionary(uniqueKeysWithValues: queue.compactMap { card in
            card.id.map { ($0, card) }
        })
        state = State()
        state.startedAt = Date()
    }

    public func nextQuestion() async throws -> Question? {
        guard !queue.isEmpty else { return nil }
        let card = queue.removeFirst()
        guard let generator = generators[card.deckId] else { return try await nextQuestion() }
        let override = resolveDirection(for: card)
        return try await generator.makeQuestion(for: card, mode: config.mode, directionOverride: override)
    }

    private func resolveDirection(for card: Card) -> CardDirection {
        switch config.direction {
        case .native:         return card.direction
        case .sourceToTarget: return .sourceToTarget
        case .targetToSource: return .targetToSource
        case .mixed:          return Bool.random() ? .sourceToTarget : .targetToSource
        }
    }

    public func recordAnswer(_ question: Question, grade: Grade) async throws {
        guard let card = cardsById[question.id] else { return }
        _ = try await cardService.grade(card: card, grade: grade)
        state.answered += 1
        state.perGrade[grade, default: 0] += 1
        if grade != .again { state.correct += 1 }
    }

    public func replaceCard(for question: Question,
                            with hit: SenseHit,
                            selectedSourceTermId: Int64,
                            selectedTargetTermId: Int64) async throws -> Question {
        guard let card = cardsById[question.id],
              let generator = generators[card.deckId] else {
            throw CardServiceError.senseNotFound
        }
        let replacement = try await cardService.replaceCard(
            card,
            with: hit,
            selectedSourceTermId: selectedSourceTermId,
            selectedTargetTermId: selectedTargetTermId
        )
        cardsById[question.id] = replacement.card
        let mode: QuizMode
        switch question.kind {
        case .flashcard: mode = .flashcard
        case .typing: mode = .typing
        case .multipleChoice: mode = .multipleChoice
        }
        return try await generator.makeQuestion(
            for: replacement.card,
            mode: mode,
            directionOverride: question.cardDirection
        )
    }

    /// Derive a grade from a typed/tapped answer.
    public static func gradeForTypedAnswer(_ raw: String, question: Question) -> Grade {
        let normalized = TextNormalizer.normalize(raw)
        guard !normalized.isEmpty else { return .again }
        if question.acceptableAnswers.contains(normalized) { return .good }
        // Small typo tolerance: Levenshtein distance 1 → hard.
        for a in question.acceptableAnswers {
            if levenshtein(normalized, a) == 1 { return .hard }
        }
        return .again
    }

    public static func gradeForChoice(_ choiceIndex: Int, question: Question) -> Grade {
        guard question.kind == .multipleChoice, let correct = question.correctIndex else { return .again }
        return choiceIndex == correct ? .good : .again
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let ac = Array(a)
        let bc = Array(b)
        if ac.isEmpty { return bc.count }
        if bc.isEmpty { return ac.count }
        var prev = Array(0...bc.count)
        var curr = Array(repeating: 0, count: bc.count + 1)
        for i in 1...ac.count {
            curr[0] = i
            for j in 1...bc.count {
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,       // insertion
                    prev[j] + 1,           // deletion
                    prev[j - 1] + cost     // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[bc.count]
    }
}
