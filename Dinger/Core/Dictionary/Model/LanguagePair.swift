import Foundation

/// A directional pair of ISO 639-1 language codes used throughout the app
/// to describe translation flow (e.g. `de → en`) and pick a dictionary.
public nonisolated struct LanguagePair: Hashable, Codable, Sendable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }

    public var reversed: LanguagePair {
        LanguagePair(source: target, target: source)
    }

    public var displayLabel: String { "\(source.uppercased())→\(target.uppercased())" }

    public static let deEN = LanguagePair(source: "de", target: "en")
}

/// Which way a lookup or card is oriented. `.auto` lets the search service
/// guess based on which language the normalized query lives in.
public nonisolated enum LookupDirection: String, Codable, Sendable, CaseIterable {
    case auto
    case sourceToTarget
    case targetToSource

    public var displayLabel: String {
        switch self {
        case .auto: return "Auto"
        case .sourceToTarget: return "DE → EN"
        case .targetToSource: return "EN → DE"
        }
    }
}
