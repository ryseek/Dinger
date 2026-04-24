import Foundation

// MARK: - Parsed types

public struct ParsedEntry: Hashable, Sendable {
    public let raw: String
    public let senses: [ParsedSense]
}

public struct ParsedSense: Hashable, Sendable {
    public let sourceTerms: [ParsedTerm]
    public let targetTerms: [ParsedTerm]
    public let domain: [String]    // ["med.", "zool."]
    public let context: String?    // parenthetical disambiguation merged
}

public struct ParsedTerm: Hashable, Sendable {
    public let surface: String         // as written (with markers), e.g. "Abbau {m}"
    public let headword: String        // markers stripped, e.g. "Abbau"
    public let normalized: String      // TextNormalizer.normalize(headword)
    public let pos: String?            // v / vt / vi / adj / adv …
    public let gender: String?         // m / f / n / pl
    public let altSpellings: [String]  // from <...>
}

// MARK: - Parser protocol

public protocol DictionaryParser {
    var sourceLanguage: String { get }
    var targetLanguage: String { get }
    func parse(line: String) -> ParsedEntry?
}

// MARK: - TU-Chemnitz implementation

public struct TuChemnitzParser: DictionaryParser {
    public let sourceLanguage: String = "de"
    public let targetLanguage: String = "en"

    public init() {}

    private static let separator = " :: "
    private static let genderTokens: Set<String> = ["m", "f", "n", "pl", "sg", "m/f", "f/m", "m/n", "n/m", "f/n", "n/f"]
    private static let posTokens: Set<String> = [
        "v", "vi", "vt", "vr", "vti", "vtr", "vrt", "vp", "vd",
        "adj", "adv", "conj", "prep", "pron", "interj", "num", "art", "det",
    ]

    public func parse(line: String) -> ParsedEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let sep = trimmed.range(of: Self.separator) else { return nil }

        let sourceSide = String(trimmed[..<sep.lowerBound])
        let targetSide = String(trimmed[sep.upperBound...])

        let sourceGroups = Self.splitRespectingBrackets(sourceSide, on: "|")
        let targetGroups = Self.splitRespectingBrackets(targetSide, on: "|")
        let groupCount = max(sourceGroups.count, targetGroups.count)

        var senses: [ParsedSense] = []
        senses.reserveCapacity(groupCount)

        for i in 0..<groupCount {
            let s = i < sourceGroups.count ? sourceGroups[i] : ""
            let t = i < targetGroups.count ? targetGroups[i] : ""
            senses.append(Self.parseSense(sourceGroup: s, targetGroup: t))
        }

        return ParsedEntry(raw: trimmed, senses: senses)
    }

    // MARK: Sense

    private static func parseSense(sourceGroup: String, targetGroup: String) -> ParsedSense {
        let (sClean, sBrackets, sParens) = stripGroupAnnotations(sourceGroup)
        let (tClean, tBrackets, tParens) = stripGroupAnnotations(targetGroup)

        let domain = Array((sBrackets + tBrackets).reduce(into: [String: Int]()) { acc, tag in
            acc[tag, default: 0] += 1
        }.keys).sorted()

        let contextPieces = sParens + tParens
        let context = contextPieces.isEmpty ? nil : contextPieces.joined(separator: "; ")

        let sourceTerms = parseTerms(from: sClean)
        let targetTerms = parseTerms(from: tClean)

        return ParsedSense(sourceTerms: sourceTerms,
                           targetTerms: targetTerms,
                           domain: domain,
                           context: context)
    }

    /// Strip `[...]` and `(...)` at the group level, returning the cleaned
    /// text (which still has `{...}` and `<...>` inside individual terms)
    /// and the extracted tags.
    private static func stripGroupAnnotations(_ group: String) -> (cleaned: String, brackets: [String], parens: [String]) {
        var cleaned = ""
        var brackets: [String] = []
        var parens: [String] = []

        var depth = (paren: 0, brace: 0, bracket: 0, angle: 0)
        var buffer = ""

        for ch in group {
            switch ch {
            case "[":
                if depth.brace == 0 && depth.paren == 0 && depth.angle == 0 {
                    depth.bracket += 1
                    buffer = ""
                } else {
                    cleaned.append(ch)
                }
            case "]":
                if depth.bracket > 0 {
                    depth.bracket -= 1
                    if depth.bracket == 0 {
                        let t = buffer.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { brackets.append(t) }
                        buffer = ""
                    }
                } else {
                    cleaned.append(ch)
                }
            case "(":
                if depth.brace == 0 && depth.bracket == 0 && depth.angle == 0 {
                    if depth.paren == 0 { buffer = "" }
                    depth.paren += 1
                } else {
                    cleaned.append(ch)
                }
            case ")":
                if depth.paren > 0 {
                    depth.paren -= 1
                    if depth.paren == 0 {
                        let t = buffer.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { parens.append(t) }
                        buffer = ""
                    }
                } else {
                    cleaned.append(ch)
                }
            default:
                if depth.bracket > 0 || depth.paren > 0 {
                    buffer.append(ch)
                } else {
                    // Track brace/angle on the cleaned stream so that later
                    // term parsing sees balanced `{...}` / `<...>`.
                    switch ch {
                    case "{": depth.brace += 1
                    case "}": if depth.brace > 0 { depth.brace -= 1 }
                    case "<": depth.angle += 1
                    case ">": if depth.angle > 0 { depth.angle -= 1 }
                    default: break
                    }
                    cleaned.append(ch)
                }
            }
        }
        return (cleaned, brackets, parens)
    }

    // MARK: Terms

    /// Split a sense-cleaned string by ';' (respecting remaining nested markers)
    /// and parse each synonym.
    private static func parseTerms(from group: String) -> [ParsedTerm] {
        let raw = group.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return [] }
        let pieces = splitRespectingBrackets(raw, on: ";")
        var out: [ParsedTerm] = []
        out.reserveCapacity(pieces.count)
        for piece in pieces {
            if let t = parseTerm(from: piece) { out.append(t) }
        }
        return out
    }

    private static func parseTerm(from raw: String) -> ParsedTerm? {
        let surface = raw.trimmingCharacters(in: .whitespaces)
        if surface.isEmpty { return nil }

        var braces: [String] = []
        var angles: [String] = []
        var text = ""

        var depth = (paren: 0, brace: 0, angle: 0)
        var buffer = ""

        for ch in surface {
            switch ch {
            case "{":
                if depth.angle == 0 && depth.paren == 0 {
                    if depth.brace == 0 { buffer = "" }
                    depth.brace += 1
                } else {
                    text.append(ch)
                }
            case "}":
                if depth.brace > 0 {
                    depth.brace -= 1
                    if depth.brace == 0 {
                        let t = buffer.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { braces.append(t) }
                        buffer = ""
                    }
                } else {
                    text.append(ch)
                }
            case "<":
                if depth.brace == 0 && depth.paren == 0 {
                    if depth.angle == 0 { buffer = "" }
                    depth.angle += 1
                } else {
                    text.append(ch)
                }
            case ">":
                if depth.angle > 0 {
                    depth.angle -= 1
                    if depth.angle == 0 {
                        let t = buffer.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { angles.append(t) }
                        buffer = ""
                    }
                } else {
                    text.append(ch)
                }
            case "(":
                depth.paren += 1
                text.append(ch)
            case ")":
                if depth.paren > 0 { depth.paren -= 1 }
                text.append(ch)
            default:
                if depth.brace > 0 || depth.angle > 0 {
                    buffer.append(ch)
                } else {
                    text.append(ch)
                }
            }
        }

        let headword = TextNormalizer.stripMarkup(text).trimmingCharacters(in: .whitespaces)
        let normalized = TextNormalizer.normalize(headword)
        if headword.isEmpty || normalized.isEmpty { return nil }

        var pos: String?
        var gender: String?
        for marker in braces {
            if gender == nil, genderTokens.contains(marker) { gender = marker }
            else if pos == nil, posTokens.contains(marker) { pos = marker }
            else if gender == nil { gender = marker }  // fallback
        }

        return ParsedTerm(surface: surface,
                          headword: headword,
                          normalized: normalized,
                          pos: pos,
                          gender: gender,
                          altSpellings: angles)
    }

    // MARK: Splitting

    /// Split a string on a single-character separator, but only when the
    /// current depth of every kind of bracket is zero. This keeps e.g.
    /// `Aal blau; blauer Aal` inside a `(...)` intact.
    static func splitRespectingBrackets(_ input: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = (paren: 0, brace: 0, bracket: 0, angle: 0)

        for ch in input {
            switch ch {
            case "(": depth.paren += 1
            case ")": if depth.paren > 0 { depth.paren -= 1 }
            case "{": depth.brace += 1
            case "}": if depth.brace > 0 { depth.brace -= 1 }
            case "[": depth.bracket += 1
            case "]": if depth.bracket > 0 { depth.bracket -= 1 }
            case "<": depth.angle += 1
            case ">": if depth.angle > 0 { depth.angle -= 1 }
            default: break
            }
            if ch == separator,
               depth.paren == 0, depth.brace == 0, depth.bracket == 0, depth.angle == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return parts
    }
}
