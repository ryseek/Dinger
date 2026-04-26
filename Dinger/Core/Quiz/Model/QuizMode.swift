import Foundation

public nonisolated enum QuizMode: String, Codable, Hashable, Sendable, CaseIterable {
    case flashcard
    case multipleChoice
    case typing
    case mixed

    public var displayLabel: String {
        switch self {
        case .flashcard:      return "Flashcard"
        case .multipleChoice: return "Multiple choice"
        case .typing:         return "Typing"
        case .mixed:          return "Mixed"
        }
    }
}

/// Which way to quiz: respect the card's saved direction, force one side,
/// or shuffle per question.
public nonisolated enum QuizDirectionMode: String, Codable, Hashable, Sendable, CaseIterable {
    case native
    case sourceToTarget
    case targetToSource
    case mixed

    public func displayLabel(for pair: LanguagePair) -> String {
        switch self {
        case .native:          return "Card default"
        case .sourceToTarget:  return "\(pair.source.uppercased()) → \(pair.target.uppercased())"
        case .targetToSource:  return "\(pair.target.uppercased()) → \(pair.source.uppercased())"
        case .mixed:           return "Both (random)"
        }
    }
}

public nonisolated struct QuizConfig: Sendable, Hashable {
    public var mode: QuizMode
    public var direction: QuizDirectionMode
    public var maxQuestions: Int
    public var includeNewCards: Bool
    public var showExamplesDuringQuestion: Bool
    /// Ignore SRS due-dates and pull every non-suspended card in the deck.
    /// Graded answers still update SRS state normally, so this is extra
    /// practice rather than a loophole that hides already-learned cards.
    public var practiceMode: Bool

    public init(mode: QuizMode = .mixed,
                direction: QuizDirectionMode = .native,
                maxQuestions: Int = 20,
                includeNewCards: Bool = true,
                showExamplesDuringQuestion: Bool = false,
                practiceMode: Bool = false) {
        self.mode = mode
        self.direction = direction
        self.maxQuestions = maxQuestions
        self.includeNewCards = includeNewCards
        self.showExamplesDuringQuestion = showExamplesDuringQuestion
        self.practiceMode = practiceMode
    }
}

public nonisolated struct QuizProgress: Sendable, Hashable {
    public let answered: Int
    public let total: Int
    public let correct: Int
    public let again: Int
    public let hard: Int
    public let good: Int
    public let easy: Int

    public static let empty = QuizProgress(answered: 0, total: 0, correct: 0, again: 0, hard: 0, good: 0, easy: 0)
}
