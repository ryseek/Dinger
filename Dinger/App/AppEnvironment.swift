import Foundation
import SwiftUI

/// Top-level dependency container shared through the SwiftUI environment.
/// Constructed once in `DingerApp` (after opening the database) and never rebuilt.
@Observable
public final class AppEnvironment {
    public let database: AppDatabase
    public let searchService: DictionarySearchService
    public let exampleSentenceService: ExampleSentenceService
    public let historyService: DictionaryHistoryService
    public let cardService: CardService
    public let defaultPair: LanguagePair
    public var lastUsedDeckId: Int64?

    public init(database: AppDatabase, defaultPair: LanguagePair = .deEN) {
        self.database = database
        self.searchService = DictionarySearchService(database: database)
        self.exampleSentenceService = ExampleSentenceService(database: database)
        self.historyService = DictionaryHistoryService(database: database)
        self.cardService = CardService(database: database)
        self.defaultPair = defaultPair
    }
}

/// Bootstrap loader. On first launch this kicks off the seed copy and
/// migrations off the main actor; the UI shows a splash until it resolves.
@Observable
@MainActor
public final class AppBootstrap {
    public struct Progress: Equatable {
        public var title: String
        public var detail: String?
        public var fractionCompleted: Double?

        public init(title: String = "Preparing dictionary...",
                    detail: String? = nil,
                    fractionCompleted: Double? = nil) {
            self.title = title
            self.detail = detail
            self.fractionCompleted = fractionCompleted
        }
    }

    public enum State {
        case loading
        case ready(AppEnvironment)
        case failed(String)
    }

    private enum BootstrapEvent: Sendable {
        case progress(AppDatabase.StartupProgress)
        case ready(AppDatabase)
        case failed(String)
    }

    public var state: State = .loading
    public var progress = Progress()

    public func load() async {
        let stream = AsyncStream<BootstrapEvent> { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let db = try AppDatabase.makeShared { step in
                        continuation.yield(.progress(step))
                    }
                    continuation.yield(.ready(db))
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
        }

        for await event in stream {
            switch event {
            case .progress(let step):
                progress = Progress(
                    title: step.title,
                    detail: step.detail,
                    fractionCompleted: step.fractionCompleted
                )
            case .ready(let db):
                self.state = .ready(AppEnvironment(database: db))
            case .failed(let message):
                self.state = .failed(message)
            }
        }
    }
}
