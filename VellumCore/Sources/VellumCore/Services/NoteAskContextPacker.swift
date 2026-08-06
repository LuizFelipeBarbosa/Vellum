import Foundation

public struct NoteAskContextPacker: Sendable {
    public struct PackedContext: Sendable, Equatable {
        public let text: String
        public let includedPages: [AskPage]
        public let wasTruncated: Bool

        public init(text: String, includedPages: [AskPage], wasTruncated: Bool) {
            self.text = text
            self.includedPages = includedPages
            self.wasTruncated = wasTruncated
        }

        public static func == (lhs: PackedContext, rhs: PackedContext) -> Bool {
            lhs.text == rhs.text
                && lhs.wasTruncated == rhs.wasTruncated
                && lhs.includedPages.count == rhs.includedPages.count
                && zip(lhs.includedPages, rhs.includedPages).allSatisfy {
                    $0.pageID == $1.pageID && $0.plainText == $1.plainText
                }
        }
    }

    public init() {}

    /// Joins every page's text in page order with a blank line. A non-nil result
    /// always contains the whole note, so `wasTruncated` is always `false`.
    public func packWholeNote(_ source: AskSource, charBudget: Int) -> PackedContext? {
        let text = source.pages.map(\.plainText).joined(separator: "\n\n")
        guard text.count <= charBudget else { return nil }
        return PackedContext(text: text, includedPages: source.pages, wasTruncated: false)
    }

    /// Retrieves paragraphs split on the exact delimiter `"\n\n"`. Each component
    /// is trimmed of surrounding whitespace and newlines, and empty components are omitted.
    public func packForQuestion(
        _ question: String,
        source: AskSource,
        charBudget: Int
    ) -> PackedContext {
        let terms = TermScoring.queryTerms(from: question)
        guard !terms.isEmpty else {
            return PackedContext(text: "", includedPages: [], wasTruncated: false)
        }

        var rankedParagraphs: [ScoredParagraph] = []
        for (pageIndex, page) in source.pages.enumerated() {
            for (paragraphIndex, paragraph) in Self.paragraphs(from: page.plainText).enumerated() {
                let score = TermScoring.occurrenceCount(
                    in: paragraph.lowercased(),
                    terms: terms
                )
                if score > 0 {
                    rankedParagraphs.append(
                        ScoredParagraph(
                            pageIndex: pageIndex,
                            paragraphIndex: paragraphIndex,
                            text: paragraph,
                            score: score
                        )
                    )
                }
            }
        }

        rankedParagraphs.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.pageIndex != $1.pageIndex {
                return $0.pageIndex < $1.pageIndex
            }
            return $0.paragraphIndex < $1.paragraphIndex
        }

        var chunks: [String] = []
        var includedPageIndices: Set<Int> = []
        var packedCharacterCount = 0
        var packedChunkWasTruncated = false
        for paragraph in rankedParagraphs {
            let chunk = "[Page \(paragraph.pageIndex + 1)]\n\(paragraph.text)"
            let separatorCount = chunks.isEmpty ? 0 : 2
            let proposedCount = packedCharacterCount + separatorCount + chunk.count

            if proposedCount > charBudget {
                if chunks.isEmpty {
                    let truncatedChunk = TokenBudget.truncateHeadAndTail(
                        chunk,
                        charBudget: charBudget - separatorCount
                    )
                    chunks.append(truncatedChunk)
                    includedPageIndices.insert(paragraph.pageIndex)
                    packedChunkWasTruncated = true
                }
                break
            }

            chunks.append(chunk)
            includedPageIndices.insert(paragraph.pageIndex)
            packedCharacterCount = proposedCount
        }

        let includedPages = source.pages.enumerated().compactMap { index, page in
            includedPageIndices.contains(index) ? page : nil
        }
        return PackedContext(
            text: chunks.joined(separator: "\n\n"),
            includedPages: includedPages,
            wasTruncated: packedChunkWasTruncated || chunks.count < rankedParagraphs.count
        )
    }

    static func paragraphs(from text: String) -> [String] {
        text.components(separatedBy: "\n\n").compactMap { component in
            let paragraph = component.trimmingCharacters(in: .whitespacesAndNewlines)
            return paragraph.isEmpty ? nil : paragraph
        }
    }
}

private struct ScoredParagraph {
    let pageIndex: Int
    let paragraphIndex: Int
    let text: String
    let score: Int
}
