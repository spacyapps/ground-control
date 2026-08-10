import Foundation

/// What a row is currently doing. Written by `cc-notify` as a plain string;
/// unknown values decode to `.idle` so a newer script can never crash the app.
enum SessionState: String, Codable, CaseIterable {
    case idle
    case working
    case needsInput
    case done

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionState(rawValue: raw) ?? .idle
    }

    /// Ranks how much a row wants your eyes. Used for sorting.
    var urgency: Int {
        switch self {
        case .needsInput: return 3
        case .working: return 2
        case .done: return 1
        case .idle: return 0
        }
    }
}
