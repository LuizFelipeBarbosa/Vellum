import Foundation

public enum TitleSuggestion {
    public static func firstSentence(from text: String) -> String {
        let delimiters: Set<Character> = [".", "!", "?", "\n"]
        let sentence = text.prefix { !delimiters.contains($0) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sentence.prefix(60))
    }
}
