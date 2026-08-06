import Foundation
import Testing
@testable import VellumCore

@Test("The first sentence stops at each supported delimiter")
func firstSentenceStopsAtSupportedDelimiters() {
    #expect(TitleSuggestion.firstSentence(from: "Period ending. Second sentence") == "Period ending")
    #expect(TitleSuggestion.firstSentence(from: "Exclamation ending! Second sentence") == "Exclamation ending")
    #expect(TitleSuggestion.firstSentence(from: "Question ending? Second sentence") == "Question ending")
    #expect(TitleSuggestion.firstSentence(from: "Line ending\nSecond line") == "Line ending")
}

@Test("The first sentence trims surrounding whitespace")
func firstSentenceTrimsSurroundingWhitespace() {
    #expect(TitleSuggestion.firstSentence(from: "  First sentence  . Second sentence") == "First sentence")
}

@Test("The first sentence is capped at 60 characters")
func firstSentenceIsCappedAt60Characters() {
    let text = String(repeating: "a", count: 61) + ". Second sentence"

    #expect(TitleSuggestion.firstSentence(from: text) == String(repeating: "a", count: 60))
}

@Test("Empty text has an empty title suggestion")
func emptyTextHasEmptyTitleSuggestion() {
    #expect(TitleSuggestion.firstSentence(from: "").isEmpty)
}
