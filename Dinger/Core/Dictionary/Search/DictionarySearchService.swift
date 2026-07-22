import Foundation
import GRDB

/// Read-only, thread-safe search against the bundled dictionary.
///
/// The service runs all queries on GRDB's reader pool so it can safely be
/// called from any actor (including the MainActor).
public nonisolated final class DictionarySearchService: @unchecked Sendable {

    public nonisolated struct SearchOptions: Sendable {
        public var limit: Int
        public var direction: LookupDirection
        public var pair: LanguagePair

        public init(limit: Int = 50,
                    direction: LookupDirection = .auto,
                    pair: LanguagePair = .deEN) {
            self.limit = limit
            self.direction = direction
            self.pair = pair
        }
    }

    private let reader: any DatabaseReader

    public init(reader: any DatabaseReader) {
        self.reader = reader
    }

    public convenience init(database: AppDatabase) {
        self.init(reader: database.dbWriter)
    }

    // MARK: - Public API

    public func search(_ query: String, options: SearchOptions = SearchOptions()) async throws -> [SenseHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let normalized = TextNormalizer.normalize(trimmed)
        guard !normalized.isEmpty else { return [] }

        let languageIds = try await resolveLanguageIds(pair: options.pair)
        let restrictLanguageId = try await restrictLanguageId(
            for: options.direction,
            query: normalized,
            pair: options.pair,
            languageIds: languageIds
        )

        return try await reader.read { [limit = options.limit] db in
            try Self.performSearch(
                db: db,
                normalized: normalized,
                limit: limit,
                restrictLanguageId: restrictLanguageId,
                pair: options.pair,
                languageIds: languageIds
            )
        }
    }

    /// Fetch the terms of a sense on both sides (grouped by language) —
    /// used by `EntryDetailView` and by `CardService` when materializing a card.
    public func senseHit(senseId: Int64, matchedTermId: Int64? = nil, pair: LanguagePair = .deEN) async throws -> SenseHit? {
        let languageIds = try await resolveLanguageIds(pair: pair)
        return try await reader.read { db in
            try Self.fetchSenseHit(
                db: db,
                senseId: senseId,
                matchedTermId: matchedTermId,
                pair: pair,
                languageIds: languageIds
            )
        }
    }

    // MARK: - Language resolution

    private func resolveLanguageIds(pair: LanguagePair) async throws -> LanguageIds {
        try await reader.read { db in
            let source = try Int64.fetchOne(db, sql: "SELECT id FROM dict.language WHERE code = ?", arguments: [pair.source])
            let target = try Int64.fetchOne(db, sql: "SELECT id FROM dict.language WHERE code = ?", arguments: [pair.target])
            guard let source, let target else { throw DictionarySearchError.languageNotFound(pair.displayLabel) }
            return LanguageIds(source: source, target: target)
        }
    }

    private func restrictLanguageId(for direction: LookupDirection,
                                    query normalized: String,
                                    pair: LanguagePair,
                                    languageIds: LanguageIds) async throws -> Int64? {
        switch direction {
        case .sourceToTarget: return languageIds.source
        case .targetToSource: return languageIds.target
        case .auto:
            // Exact matches are stronger language evidence than prefixes. For example,
            // English "car" must beat German terms beginning with "car…". Only fall
            // back to prefix evidence when neither language has an exact match.
            return try await reader.read { db in
                let prefix = Self.likeEscape(normalized) + "%"
                let rows = try Row.fetchAll(db, sql: """
                    SELECT language_id,
                           SUM(CASE WHEN normalized = ? THEN 1 ELSE 0 END) AS exact_count,
                           COUNT(*) AS prefix_count
                      FROM dict.term
                     WHERE language_id IN (?, ?)
                       AND normalized LIKE ? ESCAPE '^'
                     GROUP BY language_id
                """, arguments: [normalized, languageIds.source, languageIds.target, prefix])

                var sourceCounts = (exact: 0, prefix: 0)
                var targetCounts = (exact: 0, prefix: 0)
                for row in rows {
                    let languageId: Int64 = row["language_id"]
                    let exactCount: Int = row["exact_count"]
                    let prefixCount: Int = row["prefix_count"]
                    let counts = (exact: exactCount, prefix: prefixCount)
                    if languageId == languageIds.source { sourceCounts = counts }
                    else if languageId == languageIds.target { targetCounts = counts }
                }

                if sourceCounts.exact > 0, targetCounts.exact == 0 { return languageIds.source }
                if targetCounts.exact > 0, sourceCounts.exact == 0 { return languageIds.target }
                if sourceCounts.exact > 0, targetCounts.exact > 0 { return nil }

                if sourceCounts.prefix > 0, targetCounts.prefix == 0 { return languageIds.source }
                if targetCounts.prefix > 0, sourceCounts.prefix == 0 { return languageIds.target }
                return nil
            }
        }
    }

    // MARK: - Core query

    private struct LanguageIds {
        let source: Int64
        let target: Int64
    }

    /// Builds a ranked list of sense IDs matching the normalized query, then
    /// materializes full `SenseHit`s with both-side terms. Ranking uses a
    /// single UNION that tags each row with a priority:
    ///   0 exact, 1 prefix, 2 FTS match (+word boundary), 3 substring
    ///
    /// Duplicates across priorities are collapsed to the best rank.
    private static func performSearch(db: Database,
                                      normalized: String,
                                      limit: Int,
                                      restrictLanguageId: Int64?,
                                      pair: LanguagePair,
                                      languageIds: LanguageIds) throws -> [SenseHit] {
        let ftsEscaped = ftsEscape(normalized)
        let ftsPrefixQuery = "\"\(ftsEscaped)\"*"
        let ftsAllowedCharacters = CharacterSet.alphanumerics.union(.whitespaces)
        let ftsEnabled = normalized.unicodeScalars.allSatisfy { ftsAllowedCharacters.contains($0) }
        let likeEscaped = likeEscape(normalized)
        let likePrefix = likeEscaped + "%"
        let likeAny = "%" + likeEscaped + "%"

        var langClause = ""
        var langArg: [DatabaseValueConvertible] = []
        if let lid = restrictLanguageId {
            langClause = " AND t.language_id = ?"
            langArg = [lid]
        }

        // Single SQL: compute the best (lowest) priority per term, join to
        // sense, keep the actual best-matching term per sense, then order by
        // match quality. Exact-match ties prefer a simpler opposite-language
        // headword; lower-quality matches preserve their prior length ranking.
        let sql = """
        WITH ranked AS (
            SELECT t.id AS term_id, t.sense_id, t.language_id, 0 AS pri, LENGTH(t.headword) AS len
              FROM dict.term t
             WHERE t.normalized = ?\(langClause)

            UNION ALL

            SELECT t.id, t.sense_id, t.language_id, 1, LENGTH(t.headword)
              FROM dict.term t
             WHERE t.normalized LIKE ? ESCAPE '^'
               AND t.normalized <> ?\(langClause)

            UNION ALL

            SELECT t.id, t.sense_id, t.language_id, 2, LENGTH(t.headword)
              FROM dict.term t
              JOIN dict.term_fts f ON f.rowid = t.id
             WHERE ? AND term_fts MATCH ?\(langClause)

            UNION ALL

            SELECT t.id, t.sense_id, t.language_id, 3, LENGTH(t.headword)
              FROM dict.term t
             WHERE t.normalized LIKE ? ESCAPE '^'
               AND t.normalized NOT LIKE ? ESCAPE '^'\(langClause)
        ),
        ordered_per_sense AS (
            SELECT term_id, sense_id, language_id, pri, len,
                   ROW_NUMBER() OVER (
                       PARTITION BY sense_id
                       ORDER BY pri ASC, len ASC, term_id ASC
                   ) AS row_number
              FROM ranked
        ),
        best_per_sense AS (
            SELECT term_id AS matched_term_id, sense_id, language_id, pri, len
              FROM ordered_per_sense
             WHERE row_number = 1
        )
        SELECT bps.sense_id, bps.matched_term_id, bps.pri,
               s.entry_id, s.domain, s.context,
               t.language_id, t.surface, t.headword,
               COALESCE((
                   SELECT MIN(LENGTH(TRIM(other.normalized))
                              - LENGTH(REPLACE(TRIM(other.normalized), ' ', '')) + 1)
                     FROM dict.term other
                    WHERE other.sense_id = bps.sense_id
                      AND other.language_id <> bps.language_id
               ), 999) AS counterpart_words,
               COALESCE((
                   SELECT MIN(LENGTH(other.headword))
                     FROM dict.term other
                    WHERE other.sense_id = bps.sense_id
                      AND other.language_id <> bps.language_id
               ), 999) AS counterpart_len
          FROM best_per_sense bps
          JOIN dict.sense s ON s.id = bps.sense_id
          JOIN dict.term t ON t.id = bps.matched_term_id
         ORDER BY bps.pri ASC,
                  CASE WHEN bps.pri = 0 THEN counterpart_words ELSE 0 END ASC,
                  CASE WHEN bps.pri = 0 THEN counterpart_len ELSE 0 END ASC,
                  bps.len ASC,
                  bps.sense_id ASC
         LIMIT ?
        """

        var args: [DatabaseValueConvertible] = []
        args.append(normalized)
        args.append(contentsOf: langArg)
        args.append(likePrefix)
        args.append(normalized)
        args.append(contentsOf: langArg)
        args.append(ftsEnabled)
        args.append(ftsPrefixQuery)
        args.append(contentsOf: langArg)
        args.append(likeAny)
        args.append(likePrefix)
        args.append(contentsOf: langArg)
        args.append(limit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))

        // Materialize all senses in a second pass (N+1 on purpose: keeps the
        // ranking SQL readable; N is small — `limit` rows at most).
        var out: [SenseHit] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            let senseId: Int64 = row["sense_id"]
            let matchedTermId: Int64 = row["matched_term_id"]
            let rank: Int = row["pri"]
            if let hit = try fetchSenseHit(db: db,
                                           senseId: senseId,
                                           matchedTermId: matchedTermId,
                                           pair: pair,
                                           languageIds: languageIds,
                                           overrideRank: rank) {
                out.append(hit)
            }
        }
        return out
    }

    private static func fetchSenseHit(db: Database,
                                      senseId: Int64,
                                      matchedTermId: Int64?,
                                      pair: LanguagePair,
                                      languageIds: LanguageIds,
                                      overrideRank: Int? = nil) throws -> SenseHit? {
        guard let senseRow = try Row.fetchOne(db, sql: """
            SELECT s.id, s.entry_id, s.domain, s.context
              FROM dict.sense s WHERE s.id = ?
            """, arguments: [senseId]) else { return nil }

        let entryId: Int64 = senseRow["entry_id"]
        let domainStr: String? = senseRow["domain"]
        let context: String? = senseRow["context"]

        let termRows = try Row.fetchAll(db, sql: """
            SELECT t.id, t.language_id, t.surface, t.headword, t.pos, t.gender,
                   l.code AS lang_code
              FROM dict.term t JOIN dict.language l ON l.id = t.language_id
             WHERE t.sense_id = ?
             ORDER BY t.id
            """, arguments: [senseId])

        var source: [TermDisplay] = []
        var target: [TermDisplay] = []
        var matchedLangCode: String = pair.source

        for r in termRows {
            let termId: Int64 = r["id"]
            let langId: Int64 = r["language_id"]
            let langCode: String = r["lang_code"]
            let display = TermDisplay(
                termId: termId,
                surface: r["surface"],
                headword: r["headword"],
                pos: r["pos"],
                gender: r["gender"],
                languageCode: langCode
            )
            if langId == languageIds.source { source.append(display) }
            else if langId == languageIds.target { target.append(display) }
            if termId == matchedTermId { matchedLangCode = langCode }
        }

        let domain = (domainStr?.split(separator: ";").map(String.init)) ?? []

        return SenseHit(
            senseId: senseId,
            entryId: entryId,
            matchedTermId: matchedTermId ?? source.first?.termId ?? target.first?.termId ?? 0,
            matchedLanguageCode: matchedLangCode,
            sourceTerms: source,
            targetTerms: target,
            domain: domain,
            context: context,
            matchRank: overrideRank ?? 0
        )
    }

    // MARK: - FTS helpers

    /// Escape characters that have special meaning in FTS5 MATCH expressions.
    private static func ftsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "\"\"")
    }

    /// Escape SQL LIKE metacharacters so dictionary queries are always treated
    /// as literal text rather than patterns supplied by the user.
    private static func likeEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "^", with: "^^")
            .replacingOccurrences(of: "%", with: "^%")
            .replacingOccurrences(of: "_", with: "^_")
    }
}

public nonisolated enum DictionarySearchError: Error, LocalizedError {
    case languageNotFound(String)
    public var errorDescription: String? {
        switch self {
        case .languageNotFound(let label):
            return "Language pair \(label) not found in the dictionary."
        }
    }
}
