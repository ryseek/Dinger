import Foundation
import SwiftUI

/// Top-level dependency container shared through the SwiftUI environment.
/// Constructed once in `DingerApp` (after opening the database) and never rebuilt.
@Observable
public final class AppEnvironment {
    public let database: AppDatabase
    public let searchService: DictionarySearchService
    public let historyService: DictionaryHistoryService
    public let cardService: CardService
    public let defaultPair: LanguagePair

    public init(database: AppDatabase, defaultPair: LanguagePair = .deEN) {
        self.database = database
        self.searchService = DictionarySearchService(database: database)
        self.historyService = DictionaryHistoryService(database: database)
        self.cardService = CardService(database: database)
        self.defaultPair = defaultPair
    }
}

/// Bootstrap loader. On first launch this kicks off the seed copy and
/// migrations off the main actor; the UI shows a splash until it resolves.
@Observable
public final class AppBootstrap {
    public enum State {
        case loading
        case ready(AppEnvironment)
        case failed(String)
    }
    public var state: State = .loading

    public func load() async {
        do {
            let db = try await Task.detached(priority: .userInitiated) {
                try AppDatabase.makeShared()
            }.value
            self.state = .ready(AppEnvironment(database: db))
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }
}
