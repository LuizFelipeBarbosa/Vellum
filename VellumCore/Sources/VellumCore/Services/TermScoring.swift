import Foundation

enum TermScoring {
    static let stopwords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "do", "does", "did",
        "what", "who", "when", "where", "how", "why", "this", "in", "on", "of",
        "to", "for", "and", "or", "my", "notes", "note", "about", "tell", "me",
    ]

    static func queryTerms(from question: String) -> Set<String> {
        Set(
            question.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 3 && !stopwords.contains($0) }
        )
    }

    static func occurrenceCount(in text: String, terms: Set<String>) -> Int {
        terms.reduce(into: 0) { total, term in
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: term, range: searchStart..<text.endIndex) {
                total += 1
                searchStart = range.upperBound
            }
        }
    }

    static func excerpt(from text: String, terms: Set<String>) -> String {
        let sentences = sentenceComponents(from: text)
        var bestSentence = ""
        var bestScore = -1
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let score = occurrenceCount(in: trimmed.lowercased(), terms: terms)
            if score > bestScore {
                bestSentence = trimmed
                bestScore = score
            }
        }
        return String(bestSentence.prefix(200))
    }

    static func sentenceComponents(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
    }
}
