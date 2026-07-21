import Foundation

/// A coarse, JSON-based application boundary for non-Swift frontends.
/// Android makes one call per user intent, while all domain decisions remain
/// in DingerCore. Keeping the ABI to UTF-8 JSON also insulates the Kotlin UI
/// from Swift ABI and swift-java generator changes.
public nonisolated final class DingerBridgeEngine: @unchecked Sendable {
    private let database: AppDatabase
    private let search: DictionarySearchService
    private let examples: ExampleSentenceService
    private let history: DictionaryHistoryService
    private let cards: CardService
    private let insights: StudyInsightsService
    private let pair: LanguagePair

    private var quizSession: QuizSession?
    private var currentQuestion: Question?

    public init(database: AppDatabase, pair: LanguagePair = .deEN) {
        self.database = database
        self.search = DictionarySearchService(database: database)
        self.examples = ExampleSentenceService(database: database)
        self.history = DictionaryHistoryService(database: database)
        self.cards = CardService(database: database)
        self.insights = StudyInsightsService(database: database)
        self.pair = pair
    }

    public convenience init(databasePath: String, pair: LanguagePair = .deEN) throws {
        let database = try AppDatabase.open(at: URL(fileURLWithPath: databasePath))
        self.init(database: database, pair: pair)
    }

    public func call(_ requestJSON: String) async -> String {
        do {
            let requestData = Data(requestJSON.utf8)
            let request = try Self.decoder.decode(Request.self, from: requestData)
            switch request.action {
            case "bootstrap":
                _ = try await cards.ensureDefaultDeck(for: pair)
                async let decks = cards.allDecks()
                async let activity = insights.activity()
                async let recentSearches = history.recentSearches(pair: pair)
                async let recentOpened = recentOpenedHits()
                return try success(BootstrapPayload(
                    decks: try await decks,
                    activity: try await activity,
                    recentSearches: try await recentSearches,
                    recentOpened: try await recentOpened
                ))

            case "search":
                let query = try request.require(\.query, "query")
                let direction = request.direction.flatMap(LookupDirection.init(rawValue:)) ?? .auto
                let hits = try await search.search(
                    query,
                    options: .init(limit: request.limit ?? 80, direction: direction, pair: pair)
                )
                try? await history.recordSearch(query: query, direction: direction, pair: pair)
                return try success(hits)

            case "history":
                async let searches = history.recentSearches(pair: pair)
                async let opened = recentOpenedHits()
                return try success(HistoryPayload(
                    recentSearches: try await searches,
                    recentOpened: try await opened
                ))

            case "openSense":
                let hit = try await requiredHit(request)
                try? await history.recordOpenedSense(hit: hit, pair: pair)
                let termIds = request.termIds ?? defaultTermIds(for: hit)
                async let foundExamples = examplesForTerms(termIds)
                async let decks = cards.allDecks()
                return try success(EntryPayload(
                    hit: hit,
                    examples: try await foundExamples,
                    decks: try await decks
                ))

            case "examples":
                return try success(try await examplesForTerms(request.termIds ?? []))

            case "decks":
                _ = try await cards.ensureDefaultDeck(for: pair)
                return try success(try await cards.allDecks())

            case "createDeck":
                let name = try request.require(\.name, "name")
                return try success(try await cards.createDeck(name: name, pair: pair))

            case "renameDeck":
                let deck = try await requiredDeck(request)
                let name = try request.require(\.name, "name")
                return try success(try await cards.renameDeck(deck, to: name))

            case "deleteDeck":
                try await cards.deleteDeck(requiredDeck(request))
                return try success(MessagePayload(message: "Deck deleted"))

            case "activity":
                return try success(try await insights.activity())

            case "deckDetail":
                let deck = try await requiredDeck(request)
                async let rows = insights.cardRows(in: deck)
                async let statistics = insights.statistics(for: deck)
                return try success(DeckDetailPayload(
                    deck: deck,
                    rows: try await rows,
                    statistics: try await statistics
                ))

            case "saveCard":
                let hit = try await requiredHit(request)
                let deck = try await requiredDeck(request)
                let direction = request.cardDirection.flatMap(CardDirection.init(rawValue:)) ?? .sourceToTarget
                let result = try await cards.createCard(
                    from: hit,
                    direction: direction,
                    deck: deck,
                    selectedSourceTermIds: request.sourceTermIds,
                    selectedTargetTermIds: request.targetTermIds
                )
                return try success(CardSavePayload(
                    card: result.card,
                    isNew: result.isNew,
                    didUpdate: result.didUpdate
                ))

            case "suspendCard":
                let card = try await requiredCard(request)
                try await cards.suspend(card: card, request.suspended ?? true)
                return try success(MessagePayload(message: "Card updated"))

            case "invertCard":
                return try success(try await cards.invert(card: requiredCard(request)))

            case "deleteCard":
                try await cards.delete(card: requiredCard(request))
                return try success(MessagePayload(message: "Card deleted"))

            case "cardExample":
                let card = try await requiredCard(request)
                return try success(OptionalPayload(value: try await examples.bestExample(for: card)))

            case "exportDeck":
                let data = try await cards.exportDeck(requiredDeck(request))
                return try success(FilePayload(
                    filename: "dinger-deck.json",
                    base64: data.base64EncodedString()
                ))

            case "exportAllDecks":
                let data = try await cards.exportAllDecks()
                return try success(FilePayload(
                    filename: "dinger-all-decks-backup.json",
                    base64: data.base64EncodedString()
                ))

            case "importDecks":
                let base64 = try request.require(\.base64, "base64")
                guard let data = Data(base64Encoded: base64) else {
                    throw BridgeError.invalidParameter("base64")
                }
                return try success(try await cards.importDecks(from: data))

            case "quizStart":
                let allDecks = try await cards.allDecks()
                let selected: [Deck]
                if let deckId = request.deckId {
                    selected = allDecks.filter { $0.id == deckId }
                } else {
                    selected = allDecks
                }
                guard !selected.isEmpty else { throw BridgeError.noDecks }
                let config = QuizConfig(
                    mode: request.quizMode.flatMap(QuizMode.init(rawValue:)) ?? .mixed,
                    direction: request.quizDirection.flatMap(QuizDirectionMode.init(rawValue:)) ?? .native,
                    maxQuestions: min(max(request.maxQuestions ?? 20, 1), 100),
                    includeNewCards: request.includeNew ?? true,
                    showExamplesDuringQuestion: request.showExamples ?? false,
                    practiceMode: request.practiceMode ?? false
                )
                let session = QuizSession(
                    decks: selected,
                    config: config,
                    cardService: cards,
                    reader: database.dbWriter
                )
                try await session.start()
                quizSession = session
                currentQuestion = try await session.nextQuestion()
                return try success(quizState())

            case "quizTypedGrade":
                guard let question = currentQuestion else { throw BridgeError.noActiveQuestion }
                let answer = try request.require(\.answer, "answer")
                return try success(GradePayload(
                    grade: QuizSession.gradeForTypedAnswer(answer, question: question).rawValue
                ))

            case "quizChoiceGrade":
                guard let question = currentQuestion else { throw BridgeError.noActiveQuestion }
                let index = try request.require(\.choiceIndex, "choiceIndex")
                return try success(GradePayload(
                    grade: QuizSession.gradeForChoice(index, question: question).rawValue
                ))

            case "quizGrade":
                guard let session = quizSession,
                      let question = currentQuestion else { throw BridgeError.noActiveQuestion }
                guard let grade = request.grade.flatMap(Grade.init(rawValue:)) else {
                    throw BridgeError.invalidParameter("grade")
                }
                try await session.recordAnswer(question, grade: grade)
                currentQuestion = try await session.nextQuestion()
                return try success(quizState())

            case "quizReplace":
                guard let session = quizSession,
                      let question = currentQuestion else { throw BridgeError.noActiveQuestion }
                let hit = try await requiredHit(request)
                let source = try request.require(\.selectedSourceTermId, "selectedSourceTermId")
                let target = try request.require(\.selectedTargetTermId, "selectedTargetTermId")
                currentQuestion = try await session.replaceCard(
                    for: question,
                    with: hit,
                    selectedSourceTermId: source,
                    selectedTargetTermId: target
                )
                return try success(quizState())

            case "quizCancel":
                quizSession = nil
                currentQuestion = nil
                return try success(MessagePayload(message: "Quiz cancelled"))

            default:
                throw BridgeError.unknownAction(request.action)
            }
        } catch {
            return failure(error)
        }
    }

    private func recentOpenedHits() async throws -> [SenseHit] {
        let items = try await history.recentOpenedSenses(pair: pair)
        var hits: [SenseHit] = []
        for item in items {
            if let hit = try await search.senseHit(
                senseId: item.senseId,
                matchedTermId: item.matchedTermId,
                pair: pair
            ) {
                hits.append(hit)
            }
        }
        return hits
    }

    private func requiredHit(_ request: Request) async throws -> SenseHit {
        let senseId = try request.require(\.senseId, "senseId")
        guard let hit = try await search.senseHit(
            senseId: senseId,
            matchedTermId: request.matchedTermId,
            pair: pair
        ) else {
            throw CardServiceError.senseNotFound
        }
        return hit
    }

    private func requiredDeck(_ request: Request) async throws -> Deck {
        let id = try request.require(\.deckId, "deckId")
        guard let deck = try await cards.deck(id: id) else { throw BridgeError.deckNotFound(id) }
        return deck
    }

    private func requiredCard(_ request: Request) async throws -> Card {
        let id = try request.require(\.cardId, "cardId")
        guard let card = try await cards.card(id: id) else { throw BridgeError.cardNotFound(id) }
        return card
    }

    private func defaultTermIds(for hit: SenseHit) -> [Int64] {
        Array(hit.sourceTerms.prefix(1).map(\.termId) + hit.targetTerms.prefix(1).map(\.termId))
    }

    private func examplesForTerms(_ termIds: [Int64]) async throws -> [ExampleSentence] {
        var seen = Set<Int64>()
        var result: [ExampleSentence] = []
        for termId in termIds where termId != 0 {
            for example in try await examples.examples(for: termId, limit: 3)
            where seen.insert(example.id).inserted {
                result.append(example)
                if result.count == 3 { return result }
            }
        }
        return result
    }

    private func quizState() -> QuizStatePayload {
        let progress = quizSession?.progress ?? .empty
        return QuizStatePayload(
            question: currentQuestion,
            progress: progress,
            completed: currentQuestion == nil
        )
    }

    private func success<T: Encodable>(_ payload: T) throws -> String {
        let data = try Self.encoder.encode(Success(data: payload))
        return String(decoding: data, as: UTF8.self)
    }

    private func failure(_ error: Error) -> String {
        let payload = Failure(error: Self.bridgeErrorDescription(error))
        let data = (try? Self.encoder.encode(payload)) ?? Data("{\"ok\":false,\"error\":\"Unknown error\"}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func bridgeErrorDescription(_ error: Error) -> String {
        switch error {
        case DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context),
             DecodingError.keyNotFound(_, let context),
             DecodingError.dataCorrupted(let context):
            return "Invalid bridge request: \(context.debugDescription)"
        case EncodingError.invalidValue(_, let context):
            return "Invalid bridge response: \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct Request: Decodable {
    let action: String
    var query: String?
    var direction: String?
    var limit: Int?
    var senseId: Int64?
    var matchedTermId: Int64?
    var termIds: [Int64]?
    var deckId: Int64?
    var name: String?
    var cardId: Int64?
    var suspended: Bool?
    var base64: String?
    var sourceTermIds: [Int64]?
    var targetTermIds: [Int64]?
    var cardDirection: String?
    var quizMode: String?
    var quizDirection: String?
    var maxQuestions: Int?
    var includeNew: Bool?
    var showExamples: Bool?
    var practiceMode: Bool?
    var grade: Int?
    var answer: String?
    var choiceIndex: Int?
    var selectedSourceTermId: Int64?
    var selectedTargetTermId: Int64?

    func require<T>(_ keyPath: KeyPath<Request, T?>, _ name: String) throws -> T {
        guard let value = self[keyPath: keyPath] else { throw BridgeError.missingParameter(name) }
        return value
    }
}

private struct Success<T: Encodable>: Encodable { let ok = true; let data: T }
private struct Failure: Encodable { let ok = false; let error: String }
private struct MessagePayload: Codable { let message: String }
private struct OptionalPayload<T: Codable>: Codable { let value: T? }
private struct FilePayload: Codable { let filename: String; let base64: String }
private struct GradePayload: Codable { let grade: Int }

private struct BootstrapPayload: Codable {
    let decks: [Deck]
    let activity: StudyActivitySummary
    let recentSearches: [DictionarySearchHistoryItem]
    let recentOpened: [SenseHit]
}

private struct HistoryPayload: Codable {
    let recentSearches: [DictionarySearchHistoryItem]
    let recentOpened: [SenseHit]
}

private struct EntryPayload: Codable {
    let hit: SenseHit
    let examples: [ExampleSentence]
    let decks: [Deck]
}

private struct DeckDetailPayload: Codable {
    let deck: Deck
    let rows: [CardRow]
    let statistics: DeckStatistics
}

private struct CardSavePayload: Codable {
    let card: Card
    let isNew: Bool
    let didUpdate: Bool
}

private struct QuizStatePayload: Codable {
    let question: Question?
    let progress: QuizProgress
    let completed: Bool
}

private enum BridgeError: Error, LocalizedError {
    case unknownAction(String)
    case missingParameter(String)
    case invalidParameter(String)
    case deckNotFound(Int64)
    case cardNotFound(Int64)
    case noDecks
    case noActiveQuestion

    var errorDescription: String? {
        switch self {
        case .unknownAction(let action): return "Unknown bridge action: \(action)"
        case .missingParameter(let name): return "Missing parameter: \(name)"
        case .invalidParameter(let name): return "Invalid parameter: \(name)"
        case .deckNotFound(let id): return "Deck not found: \(id)"
        case .cardNotFound(let id): return "Card not found: \(id)"
        case .noDecks: return "No decks are available."
        case .noActiveQuestion: return "There is no active quiz question."
        }
    }
}
