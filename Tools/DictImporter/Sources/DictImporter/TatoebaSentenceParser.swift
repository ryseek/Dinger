import Foundation

public struct TatoebaSentencePair: Equatable, Sendable {
    public let germanId: Int64
    public let germanText: String
    public let englishId: Int64
    public let englishText: String

    public init(germanId: Int64, germanText: String, englishId: Int64, englishText: String) {
        self.germanId = germanId
        self.germanText = germanText
        self.englishId = englishId
        self.englishText = englishText
    }
}

public enum TatoebaSentenceParser {
    public static func parse(line: String) -> TatoebaSentencePair? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let columns = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count == 4,
              let germanId = Int64(columns[0]),
              let englishId = Int64(columns[2]) else {
            return nil
        }

        let germanText = String(columns[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let englishText = String(columns[3]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !germanText.isEmpty, !englishText.isEmpty else { return nil }

        return TatoebaSentencePair(
            germanId: germanId,
            germanText: germanText,
            englishId: englishId,
            englishText: englishText
        )
    }
}
