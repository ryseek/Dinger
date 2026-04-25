import Foundation
import GRDB

/// Turns a `Card` into a `Question` suitable for the chosen quiz mode.
/// Lives as a type rather than free functions so that it can be injected
/// with a database reader for distractor sampling.
public nonisolated final class QuestionGenerator: @unchecked Sendable {

    private let reader: any DatabaseReader
    private let deck: Deck
    private let distractorCount: Int

    public init(reader: any DatabaseReader, deck: Deck, distractorCount: Int = 3) {
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
                acceptableAnswers: normalizedAnswers,
                displayAnswers: payload.backSurfaces,
                frontExample: payload.frontExample,
                backExample: payload.backExample,
                cardDirection: effectiveDirection,
                sourceLanguageCode: deck.sourceLang,
                targetLanguageCode: deck.targetLang
            )

        case .multipleChoice:
            // Match distractors to the sense's POS bucket so a noun question
            // doesn't get adjective/verb distractors (which would leak the
            // answer). Over-fetch so that post-cleanup dedupe still yields
            // `distractorCount` distinct options.
            let rawDistractors = try await fetchDistractors(
                excludingSenseId: card.senseId,
                backLangCode: payload.backLangCode,
                bucket: payload.bucket,
                limit: distractorCount * 4
            )

            let correctCleaned = cleanForChoice(payload.backSurfaces.first ?? "?")
            let correctKey = TextNormalizer.normalize(correctCleaned)

            var seenKeys: Set<String> = [correctKey]
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
        let backSurfaces: [String]
        let frontExample: String?
        let backExample: String?
        let backLangCode: String
        let bucket: POSBucket
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
            let frontTermId: Int64
            let backTermId: Int64
            if direction == card.direction {
                frontTermId = card.frontTermId
                backTermId = card.backTermId
            } else {
                frontTermId = card.backTermId
                backTermId = card.frontTermId
            }

            let frontSurface = try String.fetchOne(db, sql: """
                SELECT t.surface FROM term t
                JOIN language l ON l.id = t.language_id
                WHERE t.id = ? AND l.code = ?
                """, arguments: [frontTermId, frontLangCode]) ?? "?"

            let backSurface = try String.fetchOne(db, sql: """
                SELECT t.surface FROM term t
                JOIN language l ON l.id = t.language_id
                WHERE t.id = ? AND l.code = ?
                """, arguments: [backTermId, backLangCode]) ?? "?"

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
            let example = try ExampleSentenceService.fetchExamples(db: db, termId: frontTermId, limit: 1).first

            return Payload(
                frontSurface: frontSurface,
                backSurfaces: [backSurface],
                frontExample: example?.text(for: frontLangCode),
                backExample: example?.text(for: backLangCode),
                backLangCode: backLangCode,
                bucket: bucket
            )
        }
    }

    private func fetchDistractors(excludingSenseId: Int64,
                                  backLangCode: String,
                                  bucket: POSBucket,
                                  limit: Int) async throws -> [String] {
        let deckId = deck.id ?? -1
        return try await reader.read { db in
            var picked: [String] = []

            if let cond = bucket.sqlCondition {
                // Same-bucket distractors: limit to senses that have at least
                // one term (on any side) matching the bucket.
                picked = try String.fetchAll(db, sql: """
                    SELECT DISTINCT t.surface FROM card c
                    JOIN term t ON t.id = c.back_term_id
                    JOIN language l ON l.id = t.language_id
                    WHERE c.deck_id = ?
                      AND c.sense_id != ?
                      AND l.code = ?
                      AND c.sense_id IN (
                          SELECT sense_id FROM term WHERE \(cond)
                      )
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [deckId, excludingSenseId, backLangCode, limit])

                if picked.count < limit {
                    let more = try String.fetchAll(db, sql: """
                        SELECT t.surface FROM term t
                        JOIN language l ON l.id = t.language_id
                        WHERE l.code = ?
                          AND t.sense_id != ?
                          AND t.sense_id IN (
                              SELECT sense_id FROM term WHERE \(cond)
                          )
                        ORDER BY RANDOM()
                        LIMIT ?
                        """, arguments: [backLangCode, excludingSenseId, limit - picked.count])
                    picked.append(contentsOf: more)
                }
            }

            // Fallback: if the bucket is unknown or didn't produce enough
            // candidates, top up with any-POS terms so the UI never shows
            // a multiple-choice question with too few options.
            if picked.count < limit {
                let more = try String.fetchAll(db, sql: """
                    SELECT DISTINCT t.surface FROM card c
                    JOIN term t ON t.id = c.back_term_id
                    JOIN language l ON l.id = t.language_id
                    WHERE c.deck_id = ? AND c.sense_id != ? AND l.code = ?
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [deckId, excludingSenseId, backLangCode, limit - picked.count])
                picked.append(contentsOf: more)
            }
            if picked.count < limit {
                let more = try String.fetchAll(db, sql: """
                    SELECT t.surface FROM term t
                    JOIN language l ON l.id = t.language_id
                    WHERE l.code = ? AND t.sense_id != ?
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [backLangCode, excludingSenseId, limit - picked.count])
                picked.append(contentsOf: more)
            }
            return picked
        }
    }

    private func stripDisplayMarkup(_ s: String) -> String {
        TextNormalizer.stripMarkup(s)
    }
}
