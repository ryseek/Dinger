import Foundation

public nonisolated enum QuestionKind: String, Codable, Hashable, Sendable {
    case flashcard
    case multipleChoice
    case typing
}

/// A single quiz prompt. For flashcard the user self-grades; for
/// multiple choice and typing the engine derives a grade from the answer.
public nonisolated struct Question: Identifiable, Hashable, Sendable {
    public let id: Int64               // card id
    public let kind: QuestionKind
    public let front: String           // prompt surface
    public let acceptableAnswers: [String]  // normalized
    public let displayAnswers: [String]     // as-shown on reveal
    public let choices: [String]       // only for multipleChoice
    public let correctIndex: Int?      // only for multipleChoice
    public let cardDirection: CardDirection
    public let sourceLanguageCode: String
    public let targetLanguageCode: String

    public init(id: Int64,
                kind: QuestionKind,
                front: String,
                acceptableAnswers: [String],
                displayAnswers: [String],
                choices: [String] = [],
                correctIndex: Int? = nil,
                cardDirection: CardDirection,
                sourceLanguageCode: String,
                targetLanguageCode: String) {
        self.id = id
        self.kind = kind
        self.front = front
        self.acceptableAnswers = acceptableAnswers
        self.displayAnswers = displayAnswers
        self.choices = choices
        self.correctIndex = correctIndex
        self.cardDirection = cardDirection
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }
}
