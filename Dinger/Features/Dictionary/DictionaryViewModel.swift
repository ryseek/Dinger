import Foundation
import Observation

@Observable
@MainActor
public final class DictionaryViewModel {
    public var query: String = ""
    public var direction: LookupDirection = .auto
    public var results: [SenseHit] = []
    public var recentSearches: [DictionarySearchHistoryItem] = []
    public var recentOpenedHits: [SenseHit] = []
    public var isSearching: Bool = false
    public var error: String?
    public var historyError: String?

    private let service: DictionarySearchService
    private let historyService: DictionaryHistoryService
    private let pair: LanguagePair
    private var searchTask: Task<Void, Never>?

    public init(service: DictionarySearchService, historyService: DictionaryHistoryService, pair: LanguagePair = .deEN) {
        self.service = service
        self.historyService = historyService
        self.pair = pair
    }

    public func onQueryChanged() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            results = []
            error = nil
            isSearching = false
            searchTask = nil
            return
        }
        let currentDirection = direction
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms debounce
            if Task.isCancelled { return }
            await self?.performSearch(query: trimmed, direction: currentDirection)
        }
    }

    public func onDirectionChanged() {
        onQueryChanged()
    }

    private func performSearch(query: String, direction: LookupDirection) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let options = DictionarySearchService.SearchOptions(limit: 80, direction: direction, pair: pair)
            let hits = try await service.search(query, options: options)
            if Task.isCancelled { return }
            results = hits
            error = nil
            try? await historyService.recordSearch(query: query, direction: direction, pair: pair)
            await loadHistory()
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }
    }

    public func openSearch(_ item: DictionarySearchHistoryItem) {
        direction = item.direction
        query = item.query
        onQueryChanged()
    }

    public func recordOpened(_ hit: SenseHit) async {
        do {
            try await historyService.recordOpenedSense(hit: hit, pair: pair)
            await loadHistory()
        } catch {
            historyError = error.localizedDescription
        }
    }

    public func loadHistory() async {
        do {
            async let searches = historyService.recentSearches(pair: pair)
            async let opened = loadOpenedHits()
            recentSearches = try await searches
            recentOpenedHits = try await opened
            historyError = nil
        } catch {
            historyError = error.localizedDescription
        }
    }

    private func loadOpenedHits() async throws -> [SenseHit] {
        let history = try await historyService.recentOpenedSenses(pair: pair)
        var hits: [SenseHit] = []
        hits.reserveCapacity(history.count)
        for item in history {
            if let hit = try await service.senseHit(senseId: item.senseId, matchedTermId: item.matchedTermId, pair: pair) {
                hits.append(hit)
            }
        }
        return hits
    }
}
