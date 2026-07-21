import Foundation
import GRDB

/// Turns a `Card` into a `Question` suitable for the chosen quiz mode.
/// Lives as a type rather than free functions so that it can be injected
/// with a database reader for distractor sampling.
public nonisolated final class QuestionGenerator: @unchecked Sendable {

    private let reader: any DatabaseReader
    private let deck: Deck
    private let distractorCount: Int

    public init(reader: any DatabaseReader, deck: Deck, distractorCount: Int = 7) {
        self.reader = reader
        self.deck = deck
        self.distractorCount = distractorCount
    }

    public func makeQuestion(for card: Card,
                             mode: QuizMode,
                             directionOverride: CardDirection? = nil) async throws -> Question {
        let kind = resolveKind(for: mode)
        let effectiveDirection = directionOverride ?? card.direction
        let payload = try await fetchPayload(for: card, direction: effectiveDirection)

        let normalizedAnswers = payload.backSurfaces.map { TextNormalizer.normalize(stripDisplayMarkup($0)) }
            .filter { !$0.isEmpty }

        switch kind {
        case .flashcard:
            return Question(
                id: card.id ?? 0,
                kind: .flashcard,
                front: payload.frontSurface,
                displayFronts: payload.frontSurfaces,
                acceptableAnswers: normalizedAnswers,
                displayAnswers: payload.backSurfaces,
                frontExample: payload.frontExample,
                backExample: payload.backExample,
                cardDirection: effectiveDirection,
                sourceLanguageCode: deck.sourceLang,
                targetLanguageCode: deck.targetLang
            )

        case .typing:
            return Question(
                id: card.id ?? 0,
                kind: .typing,
                front: payload.frontSurface,
                displayFronts: payload.frontSurfaces,
                acceptableAnswers: normalizedAnswers,
                displayAnswers: payload.backSurfaces,
                frontExample: payload.frontExample,
                backExample: payload.backExample,
                cardDirection: effectiveDirection,
                sourceLanguageCode: deck.sourceLang,
                targetLanguageCode: deck.targetLang
            )

        case .multipleChoice:
            // Blend same-category vocabulary from personal cards and the
            // dictionary. Over-fetch so post-cleanup dedupe still yields
            // `distractorCount` distinct options.
            let rawDistractors = try await fetchDistractors(
                excludingSenseId: card.senseId,
                frontLangCode: payload.frontLangCode,
                backLangCode: payload.backLangCode,
                frontSurface: payload.frontSurface,
                correctSurfaces: payload.backSurfaces,
                bucket: payload.bucket,
                limit: distractorCount * 4
            )

            let correctOptions = payload.backSurfaces.map { cleanForChoice($0) }
                .filter { !$0.isEmpty }
            let correctCleaned = correctOptions.randomElement() ?? "?"
            let correctKeys = Set(correctOptions.map { TextNormalizer.normalize($0) })

            var seenKeys = correctKeys
            var cleanedDistractors: [String] = []
            for raw in rawDistractors {
                let cleaned = cleanForChoice(raw)
                guard !cleaned.isEmpty else { continue }
                let key = TextNormalizer.normalize(cleaned)
                guard seenKeys.insert(key).inserted else { continue }
                cleanedDistractors.append(cleaned)
                if cleanedDistractors.count >= distractorCount { break }
            }

            var choicePool = cleanedDistractors
            choicePool.append(correctCleaned)
            choicePool.shuffle()
            let idx = choicePool.firstIndex(of: correctCleaned) ?? 0

            return Question(
                id: card.id ?? 0,
                kind: .multipleChoice,
                front: payload.frontSurface,
                displayFronts: payload.frontSurfaces,
                acceptableAnswers: normalizedAnswers,
                displayAnswers: payload.backSurfaces,
                frontExample: payload.frontExample,
                backExample: payload.backExample,
                choices: choicePool,
                correctIndex: idx,
                cardDirection: effectiveDirection,
                sourceLanguageCode: deck.sourceLang,
                targetLanguageCode: deck.targetLang
            )
        }
    }

    /// Surface text for a multiple-choice button: stripped of gender/POS/domain
    /// markup so those don't leak the correct answer. The reveal screen still
    /// shows the full surface from `displayAnswers`.
    private func cleanForChoice(_ surface: String) -> String {
        stripDisplayMarkup(surface)
    }

    private func resolveKind(for mode: QuizMode) -> QuestionKind {
        switch mode {
        case .flashcard:      return .flashcard
        case .multipleChoice: return .multipleChoice
        case .typing:         return .typing
        case .mixed:
            return [QuestionKind.flashcard, .multipleChoice, .typing].randomElement()!
        }
    }

    // MARK: - POS bucket

    /// Coarse POS bucket for distractor matching. TU-Chemnitz encodes noun
    /// gender as `{m}`/`{f}`/`{n}`/`{pl}`, so nouns are detected by
    /// *"has a non-null gender"* rather than any noun-specific pos tag.
    private enum POSBucket: String {
        case noun, verb, adj, adv, other

        /// `nil` = no filter; used for `.other` and fallbacks.
        var sqlCondition: String? {
            switch self {
            case .noun:  return "gender IS NOT NULL"
            case .verb:  return "LOWER(pos) LIKE 'v%'"
            case .adj:   return "LOWER(pos) = 'adj'"
            case .adv:   return "LOWER(pos) = 'adv'"
            case .other: return nil
            }
        }
    }

    private static func classify(pos: String?, gender: String?) -> POSBucket {
        if gender != nil { return .noun }
        guard let p = pos?.lowercased(), !p.isEmpty else { return .other }
        if p == "adj" { return .adj }
        if p == "adv" { return .adv }
        if p.hasPrefix("v") { return .verb }
        return .other
    }

    // MARK: - Payload

    private struct Payload {
        let frontSurface: String
        let frontSurfaces: [String]
        let backSurfaces: [String]
        let frontExample: String?
        let backExample: String?
        let frontLangCode: String
        let backLangCode: String
        let bucket: POSBucket
    }

    private struct TermSurface {
        let termId: Int64
        let surface: String
    }

    private func fetchPayload(for card: Card, direction: CardDirection) async throws -> Payload {
        let frontLangCode: String
        let backLangCode: String
        switch direction {
        case .sourceToTarget:
            frontLangCode = deck.sourceLang
            backLangCode = deck.targetLang
        case .targetToSource:
            frontLangCode = deck.targetLang
            backLangCode = deck.sourceLang
        }

        return try await reader.read { db in
            let frontTermIds: [Int64]
            let backTermIds: [Int64]
            if direction == card.direction {
                frontTermIds = card.frontTermIds
                backTermIds = card.backTermIds
            } else {
                frontTermIds = card.backTermIds
                backTermIds = card.frontTermIds
            }

            let frontTerms = try Self.fetchTermSurfaces(db: db, termIds: frontTermIds, languageCode: frontLangCode)
            let backTerms = try Self.fetchTermSurfaces(db: db, termIds: backTermIds, languageCode: backLangCode)
            let promptTerm = frontTerms.randomElement()
            let textOverrides = card.textOverrides(for: direction)
            let frontSurfaces = textOverrides.front.map { [$0] } ?? frontTerms.map(\.surface)
            let backSurfaces = textOverrides.back.map { [$0] } ?? backTerms.map(\.surface)

            // Determine POS/gender from any term on the sense, preferring
            // one that has a gender (noun) or POS set. English terms are
            // usually unmarked, so we look across both sides of the sense.
            let markers = try Row.fetchAll(db, sql: """
                SELECT pos, gender FROM term WHERE sense_id = ?
                """, arguments: [card.senseId])
            var pos: String? = nil
            var gender: String? = nil
            for row in markers {
                if gender == nil, let g: String = row["gender"] { gender = g }
                if pos == nil,    let p: String = row["pos"]    { pos = p }
                if gender != nil, pos != nil { break }
            }
            let bucket = Self.classify(pos: pos, gender: gender)
            let example = try promptTerm.flatMap {
                try ExampleSentenceService.fetchExamples(db: db, termId: $0.termId, limit: 1).first
            }

            return Payload(
                frontSurface: textOverrides.front ?? promptTerm?.surface ?? "?",
                frontSurfaces: frontSurfaces,
                backSurfaces: backSurfaces,
                frontExample: example?.text(for: frontLangCode),
                backExample: example?.text(for: backLangCode),
                frontLangCode: frontLangCode,
                backLangCode: backLangCode,
                bucket: bucket
            )
        }
    }

    private static func fetchTermSurfaces(db: Database, termIds: [Int64], languageCode: String) throws -> [TermSurface] {
        guard !termIds.isEmpty else { return [] }
        return try termIds.compactMap { termId in
            guard let surface = try String.fetchOne(db, sql: """
                SELECT t.surface FROM term t
                JOIN language l ON l.id = t.language_id
                WHERE t.id = ? AND l.code = ?
                """, arguments: [termId, languageCode]) else {
                return nil
            }
            return TermSurface(termId: termId, surface: surface)
        }
    }

    private struct DistractorCandidate {
        let surface: String
        let sharesPromptTranslation: Bool
    }

    private func fetchDistractors(excludingSenseId: Int64,
                                  frontLangCode: String,
                                  backLangCode: String,
                                  frontSurface: String,
                                  correctSurfaces: [String],
                                  bucket: POSBucket,
                                  limit: Int) async throws -> [String] {
        return try await reader.read { db in
            let poolLimit = max(limit, 12)
            let frontKey = TextNormalizer.normalize(stripDisplayMarkup(frontSurface))

            let cardWords: [DistractorCandidate]
            let dictionaryWords: [DistractorCandidate]
            if let cond = bucket.sqlCondition {
                // Pull same-category vocabulary from every personal deck.
                // Joining through the sense makes this direction-independent.
                let cardRows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT t.surface,
                           EXISTS (
                               SELECT 1
                                 FROM term clue
                                 JOIN language clue_language ON clue_language.id = clue.language_id
                                WHERE clue.sense_id = t.sense_id
                                  AND clue_language.code = ?
                                  AND clue.normalized = ?
                           ) AS semantic_match
                      FROM card c
                      JOIN term t ON t.sense_id = c.sense_id
                      JOIN language l ON l.id = t.language_id
                     WHERE c.sense_id != ?
                       AND l.code = ?
                       AND c.sense_id IN (
                           SELECT sense_id FROM term WHERE \(cond)
                       )
                     ORDER BY RANDOM()
                     LIMIT ?
                    """, arguments: [frontLangCode, frontKey, excludingSenseId, backLangCode, poolLimit])
                cardWords = Self.candidates(from: cardRows)

                let dictionaryRows = try Row.fetchAll(db, sql: """
                    SELECT t.surface,
                           EXISTS (
                               SELECT 1
                                 FROM term clue
                                 JOIN language clue_language ON clue_language.id = clue.language_id
                                WHERE clue.sense_id = t.sense_id
                                  AND clue_language.code = ?
                                  AND clue.normalized = ?
                           ) AS semantic_match
                      FROM term t
                    JOIN language l ON l.id = t.language_id
                    WHERE l.code = ?
                      AND t.sense_id != ?
                      AND t.sense_id IN (
                          SELECT sense_id FROM term WHERE \(cond)
                      )
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [frontLangCode, frontKey, backLangCode, excludingSenseId, poolLimit])
                dictionaryWords = Self.candidates(from: dictionaryRows)
            } else {
                let cardRows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT t.surface,
                           EXISTS (
                               SELECT 1
                                 FROM term clue
                                 JOIN language clue_language ON clue_language.id = clue.language_id
                                WHERE clue.sense_id = t.sense_id
                                  AND clue_language.code = ?
                                  AND clue.normalized = ?
                           ) AS semantic_match
                      FROM card c
                      JOIN term t ON t.sense_id = c.sense_id
                      JOIN language l ON l.id = t.language_id
                     WHERE c.sense_id != ? AND l.code = ?
                     ORDER BY RANDOM()
                     LIMIT ?
                    """, arguments: [frontLangCode, frontKey, excludingSenseId, backLangCode, poolLimit])
                cardWords = Self.candidates(from: cardRows)
                let dictionaryRows = try Row.fetchAll(db, sql: """
                    SELECT t.surface,
                           EXISTS (
                               SELECT 1
                                 FROM term clue
                                 JOIN language clue_language ON clue_language.id = clue.language_id
                                WHERE clue.sense_id = t.sense_id
                                  AND clue_language.code = ?
                                  AND clue.normalized = ?
                           ) AS semantic_match
                      FROM term t
                    JOIN language l ON l.id = t.language_id
                    WHERE l.code = ? AND t.sense_id != ?
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [frontLangCode, frontKey, backLangCode, excludingSenseId, poolLimit])
                dictionaryWords = Self.candidates(from: dictionaryRows)
            }

            // If another sense has the exact same prompt translation, it is
            // also a valid answer without sentence context (for example,
            // wissen/kennen for "know"). Never use it as a false distractor.
            let rankedCards = Self.rank(
                cardWords.filter { !$0.sharesPromptTranslation },
                against: correctSurfaces
            )
            let rankedDictionary = Self.rank(
                dictionaryWords.filter { !$0.sharesPromptTranslation },
                against: correctSurfaces
            )
            return Self.interleave([rankedCards, rankedDictionary])
        }
    }

    private static func candidates(from rows: [Row]) -> [DistractorCandidate] {
        rows.map {
            DistractorCandidate(
                surface: $0["surface"],
                sharesPromptTranslation: ($0["semantic_match"] as Int? ?? 0) != 0
            )
        }
    }

    private static func rank(_ candidates: [DistractorCandidate], against correctSurfaces: [String]) -> [String] {
        candidates.enumerated().sorted { lhs, rhs in
            let leftScore = confusionScore(lhs.element, correctSurfaces: correctSurfaces)
            let rightScore = confusionScore(rhs.element, correctSurfaces: correctSurfaces)
            if leftScore == rightScore { return lhs.offset < rhs.offset }
            return leftScore > rightScore
        }.map(\.element.surface)
    }

    private static func confusionScore(_ candidate: DistractorCandidate, correctSurfaces: [String]) -> Double {
        let candidateKey = TextNormalizer.normalize(TextNormalizer.stripMarkup(candidate.surface))
        let candidateMarkers = grammarMarkers(in: candidate.surface)
        var best = 0.0

        for correct in correctSurfaces {
            let correctKey = TextNormalizer.normalize(TextNormalizer.stripMarkup(correct))
            guard !correctKey.isEmpty, !candidateKey.isEmpty else { continue }
            let correctMarkers = grammarMarkers(in: correct)
            let sharedMarkers = candidateMarkers.intersection(correctMarkers).count
            let markerScore = Double(sharedMarkers) * 8
                + (!correctMarkers.isEmpty && candidateMarkers == correctMarkers ? 5 : 0)

            let distance = levenshtein(candidateKey, correctKey)
            let longest = max(max(candidateKey.count, correctKey.count), 1)
            let spellingScore = max(0, 1 - Double(distance) / Double(longest)) * 10
            let lengthScore = max(0, 1 - Double(abs(candidateKey.count - correctKey.count)) / Double(longest))
            best = max(best, markerScore + spellingScore + lengthScore)
        }
        return best
    }

    private static func grammarMarkers(in surface: String) -> Set<String> {
        let key = TextNormalizer.normalize(surface)
        let markerGroups: [(String, [String])] = [
            ("sich", ["sich"]),
            ("dative-person", ["jdm", "jdm.", "jemandem"]),
            ("accusative-person", ["jdn", "jdn.", "jemanden"]),
            ("thing", ["etw", "etw.", "etwas"])
        ]
        return Set(markerGroups.compactMap { marker, spellings in
            spellings.contains { key.range(of: $0) != nil } ? marker : nil
        })
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let cost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    current[rightIndex - 1] + 1,
                    previous[rightIndex] + 1,
                    previous[rightIndex - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    private static func interleave(_ pools: [[String]]) -> [String] {
        var indices = Array(repeating: 0, count: pools.count)
        var result: [String] = []
        var addedValue = true
        while addedValue {
            addedValue = false
            for poolIndex in pools.indices where indices[poolIndex] < pools[poolIndex].count {
                result.append(pools[poolIndex][indices[poolIndex]])
                indices[poolIndex] += 1
                addedValue = true
            }
        }
        return result
    }

    private func stripDisplayMarkup(_ s: String) -> String {
        TextNormalizer.stripMarkup(s)
    }
}
