import Foundation
import Observation

@Observable
@MainActor
public final class QuizStartViewModel {
    public var decks: [Deck] = []
    /// `nil` means every deck; otherwise this is the selected deck id.
    public var selectedDeckId: Int64? {
        didSet {
            defaults.set(selectedDeckId.map(String.init) ?? "all", forKey: Keys.deckSelection)
        }
    }
    public var mode: QuizMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }
    public var direction: QuizDirectionMode {
        didSet { defaults.set(direction.rawValue, forKey: Keys.direction) }
    }
    public var maxQuestions: Int {
        didSet { defaults.set(maxQuestions, forKey: Keys.maxQuestions) }
    }
    public var includeNew: Bool {
        didSet { defaults.set(includeNew, forKey: Keys.includeNew) }
    }
    public var showExamplesDuringQuestion: Bool {
        didSet { defaults.set(showExamplesDuringQuestion, forKey: Keys.showExamples) }
    }
    public var practiceMode: Bool {
        didSet { defaults.set(practiceMode, forKey: Keys.practiceMode) }
    }
    public var error: String?

    private let service: CardService
    private let defaults: UserDefaults

    private enum Keys {
        static let deckSelection = "quiz.last.deckSelection"
        static let mode = "quiz.last.mode"
        static let direction = "quiz.last.direction"
        static let maxQuestions = "quiz.last.maxQuestions"
        static let includeNew = "quiz.last.includeNew"
        static let showExamples = "quiz.last.showExamples"
        static let practiceMode = "quiz.last.practiceMode"
    }

    public init(service: CardService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults

        let storedDeck = defaults.string(forKey: Keys.deckSelection)
        self.selectedDeckId = storedDeck.flatMap { $0 == "all" ? nil : Int64($0) }
        self.mode = defaults.string(forKey: Keys.mode)
            .flatMap(QuizMode.init(rawValue:)) ?? .mixed
        self.direction = defaults.string(forKey: Keys.direction)
            .flatMap(QuizDirectionMode.init(rawValue:)) ?? .native
        let storedQuestionCount = defaults.object(forKey: Keys.maxQuestions) as? Int ?? 10
        self.maxQuestions = min(max(storedQuestionCount, 5), 50)
        self.includeNew = defaults.object(forKey: Keys.includeNew) as? Bool ?? true
        self.showExamplesDuringQuestion = defaults.object(forKey: Keys.showExamples) as? Bool ?? false
        self.practiceMode = defaults.object(forKey: Keys.practiceMode) as? Bool ?? false
    }

    public func load() async {
        do {
            decks = try await service.allDecks()
            if let selectedDeckId, !decks.contains(where: { $0.id == selectedDeckId }) {
                self.selectedDeckId = nil
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public var selectedDecks: [Deck] {
        guard let selectedDeckId else { return decks }
        return decks.filter { $0.id == selectedDeckId }
    }

    public var selectedDeck: Deck? {
        guard let selectedDeckId else { return nil }
        return decks.first { $0.id == selectedDeckId }
    }

    public func makeConfig() -> QuizConfig {
        QuizConfig(mode: mode,
                   direction: direction,
                   maxQuestions: maxQuestions,
                   includeNewCards: includeNew,
                   showExamplesDuringQuestion: showExamplesDuringQuestion,
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

    public func replaceCurrentCard(with hit: SenseHit,
                                   selectedSourceTermId: Int64,
                                   selectedTargetTermId: Int64) async {
        guard case let .reveal(question, inferredGrade) = phase else { return }
        do {
            let refreshed = try await session.replaceCard(
                for: question,
                with: hit,
                selectedSourceTermId: selectedSourceTermId,
                selectedTargetTermId: selectedTargetTermId
            )
            phase = .reveal(refreshed, inferredGrade)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}
