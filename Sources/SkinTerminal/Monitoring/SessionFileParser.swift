import Foundation

/// Reads a `.jsonl` file and returns its current state.
///
/// Only the last decodable line matters (docs/SPEC.md §2). Lines are scanned
/// from the end so a half-written trailing line — a real possibility while a
/// hook is appending — falls back to the previous good one instead of
/// blanking the row.
enum SessionFileParser {
    static func latestEvent(at url: URL) -> SessionEvent? {
        latest(at: url, as: SessionEvent.self)
    }

    static func latestAgentEvent(at url: URL) -> AgentEvent? {
        latest(at: url, as: AgentEvent.self)
    }

    private static func latest<T: Decodable>(at url: URL, as type: T.Type) -> T? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let decoder = JSONDecoder()
        for line in contents.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            if let decoded = try? decoder.decode(type, from: data) { return decoded }
        }
        return nil
    }
}
