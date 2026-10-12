import Foundation

public enum PromptBulkImport {
    /// Splits pasted day plans into prompts.
    /// Prefers blank-line separated blocks; falls back to single newlines when that yields more than one line.
    public static func prompts(from raw: String) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let blocks = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if blocks.count > 1 {
            return blocks
        }

        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines.map(String.init)
        }

        return [normalized]
    }

    public static func titleHint(for prompt: String) -> String {
        let first = prompt.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? prompt
        return String(first.prefix(72))
    }
}
