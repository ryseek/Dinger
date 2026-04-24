import Foundation

// Dev-time copy of the runtime normalizer. Kept in sync with
// Dinger/Core/Dictionary/Normalize/TextNormalizer.swift. If you change the
// folding pipeline here you MUST regenerate de-en.sqlite.
public enum TextNormalizer {

    public static func normalize(_ input: String) -> String {
        let lowered = input.lowercased()
        let umlautFolded = foldGermanUmlauts(lowered)
        let diacriticFolded = umlautFolded
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
        return collapseWhitespace(diacriticFolded)
    }

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
            case "ä", "Ä": out.append("ae")
            case "ö", "Ö": out.append("oe")
            case "ü", "Ü": out.append("ue")
            case "ß":     out.append("ss")
            default:      out.unicodeScalars.append(scalar)
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
