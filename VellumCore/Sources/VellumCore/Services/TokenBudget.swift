import Foundation

public enum TokenBudget {
    /// Estimates tokens as `ceil(characterCount / 3.5 * 1.2)`, adding 20% headroom
    /// to a conservative 3.5-characters-per-token estimate.
    public static func estimatedTokens(forCharacterCount characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return Int(ceil(Double(characterCount) / 3.5 * 1.2))
    }

    /// Keeps approximately 80% of the available content characters from the head
    /// and 20% from the tail, with an ellipsis marker between them.
    public static func truncateHeadAndTail(_ text: String, charBudget: Int) -> String {
        guard charBudget > 0 else { return "" }
        guard text.count > charBudget else { return text }

        let preferredMarker = "\n…\n"
        let marker = charBudget >= preferredMarker.count ? preferredMarker : "…"
        let contentBudget = charBudget - marker.count
        let headCount = contentBudget * 4 / 5
        let tailCount = contentBudget - headCount

        return String(text.prefix(headCount)) + marker + String(text.suffix(tailCount))
    }
}
