import Foundation

/// User's self-reported or inferred success on a card review.
/// Backed by an integer 0..3 stored in `review_log.grade`.
public nonisolated enum Grade: Int, Codable, Hashable, Sendable, CaseIterable {
    case again = 0
    case hard  = 1
    case good  = 2
    case easy  = 3

    public var displayLabel: String {
        switch self {
        case .again: return "Again"
        case .hard:  return "Hard"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    public var isLapse: Bool { self == .again }
}
