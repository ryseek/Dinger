import Foundation

/// Language-aware normalization used both when indexing dictionary terms
/// and when normalizing user queries. The goal is "typed it how I remember it"
/// matching: case-folded, diacritic-folded, German umlaut-folded.
public nonisolated enum TextNormalizer {

    /// Fold a string to its canonical search key.
    ///
    /// Pipeline:
    /// 1. Lowercase (locale-insensitive).
    /// 2. German umlaut fold: ä→ae, ö→oe, ü→ue, ß→ss (applied before diacritic strip
    ///    so that users who type "abanderung" *or* "aenderung" both hit "Änderung").
    /// 3. Diacritic strip for other languages (é→e, ñ→n, …).
    /// 4. Whitespace trim + collapse.
    public static func normalize(_ input: String) -> String {
        let lowered = input.lowercased()
        let umlautFolded = foldGermanUmlauts(lowered)
        let diacriticFolded = umlautFolded
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
        return collapseWhitespace(diacriticFolded)
    }

    /// Strip dictionary markup that isn't part of the headword, returning
    /// only the bare word(s) suitable for storing as `headword`.
    ///
    /// For instance `"Abbau {m}; Abbauen {n}"` → `"Abbau; Abbauen"`.
    /// Does NOT split synonyms — callers split by `;` themselves.
    public static func stripMarkup(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var angleDepth = 0
        for ch in input {
            switch ch {
            case "(": parenDepth += 1
            case ")": if parenDepth > 0 { parenDepth -= 1 }
            case "{": braceDepth += 1
            case "}": if braceDepth > 0 { braceDepth -= 1 }
            case "[": bracketDepth += 1
            case "]": if bracketDepth > 0 { bracketDepth -= 1 }
            case "<": angleDepth += 1
            case ">": if angleDepth > 0 { angleDepth -= 1 }
            default:
                if parenDepth == 0 && braceDepth == 0 && bracketDepth == 0 && angleDepth == 0 {
                    out.append(ch)
                }
            }
        }
        return collapseWhitespace(out)
    }

    private static func foldGermanUmlauts(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 4)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "ä": out.append("ae")
            case "ö": out.append("oe")
            case "ü": out.append("ue")
            case "ß": out.append("ss")
            case "Ä": out.append("ae")
            case "Ö": out.append("oe")
            case "Ü": out.append("ue")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func collapseWhitespace(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var lastWasSpace = true
        for ch in s {
            if ch.isWhitespace {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }
}
