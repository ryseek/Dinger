import Foundation
import Observation

@Observable
@MainActor
public final class QuizStartViewModel {
    public var decks: [Deck] = []
    public var selectedDeck: Deck?
    public var mode: QuizMode = .mixed
    public var direction: QuizDirectionMode = .native
    public var maxQuestions: Int = 10
    public var includeNew: Bool = true
    public var practiceMode: Bool = false
    public var error: String?

    private let service: CardService

    public init(service: CardService) {
        self.service = service
    }

    public func load() async {
        do {
            decks = try await service.allDecks()
            if selectedDeck == nil { selectedDeck = decks.first }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func makeConfig() -> QuizConfig {
        QuizConfig(mode: mode,
                   direction: direction,
                   maxQuestions: maxQuestions,
                   includeNewCards: includeNew,
                   practiceMode: practiceMode)
    }
}

@Observable
@MainActor
public final class QuizPlayViewModel {
    public enum Phase: Sendable {
        case loading
        case question(Question)
        case reveal(Question, Grade?)  // .reveal with optional inferred grade
        case done(QuizProgress)
        case empty
        case error(String)
    }

    public var phase: Phase = .loading
    public var progress: QuizProgress = .empty
    public var typedAnswer: String = ""
    public var selectedChoice: Int?

    private let session: QuizSession

    public init(session: QuizSession) {
        self.session = session
    }

    public func start() async {
        do {
            try await session.start()
            await advance()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func advance() async {
        do {
            if let q = try await session.nextQuestion() {
                typedAnswer = ""
                selectedChoice = nil
                phase = .question(q)
            } else {
                phase = .done(session.progress)
            }
            progress = session.progress
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func reveal(currentQuestion q: Question, inferredGrade: Grade? = nil) {
        phase = .reveal(q, inferredGrade)
    }

    public func submitGrade(_ grade: Grade) async {
        guard case let .reveal(q, _) = phase else { return }
        do {
            try await session.recordAnswer(q, grade: grade)
            progress = session.progress
            await advance()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public func submitTypedAnswer() async {
        guard case let .question(q) = phase else { return }
        let grade = QuizSession.gradeForTypedAnswer(typedAnswer, question: q)
        phase = .reveal(q, grade)
    }

    public func submitChoice(_ index: Int) async {
        guard case let .question(q) = phase else { return }
        selectedChoice = index
        let grade = QuizSession.gradeForChoice(index, question: q)
        phase = .reveal(q, grade)
    }

    public func flashcardReveal() {
        guard case let .question(q) = phase else { return }
        phase = .reveal(q, nil)
    }
}
