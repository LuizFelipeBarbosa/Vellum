import Foundation
import Testing
@testable import VellumCore

@Test("Whole-note packing returns all page text when it fits")
func wholeNotePackingFits() {
    let first = AskPage(pageID: UUID(), plainText: "Alpha")
    let second = AskPage(pageID: UUID(), plainText: "Beta")
    let source = makeAskSource(pages: [first, second])

    let packed = NoteAskContextPacker().packWholeNote(source, charBudget: 11)

    #expect(packed?.text == "Alpha\n\nBeta")
    #expect(packed?.includedPages.map(\.pageID) == [first.pageID, second.pageID])
    #expect(packed?.wasTruncated == false)
}

@Test("Whole-note packing returns nil when the complete text exceeds budget")
func wholeNotePackingExceedsBudget() {
    let source = makeAskSource(pages: [
        AskPage(pageID: UUID(), plainText: "Alpha"),
        AskPage(pageID: UUID(), plainText: "Beta"),
    ])

    #expect(NoteAskContextPacker().packWholeNote(source, charBudget: 10) == nil)
}

@Test("Question packing ranks the strongest paragraph first")
func questionPackingRanksParagraphs() throws {
    let source = makeAskSource(pages: [
        AskPage(
            pageID: UUID(),
            plainText: "Comet appears once.\n\nAn orchard grows quietly.\n\nComet comet appears twice."
        )
    ])

    let packed = NoteAskContextPacker().packForQuestion(
        "Tell me about comet",
        source: source,
        charBudget: 200
    )

    let strongest = try #require(packed.text.range(of: "Comet comet appears twice."))
    let weaker = try #require(packed.text.range(of: "Comet appears once."))
    #expect(strongest.lowerBound < weaker.lowerBound)
    #expect(!packed.text.contains("orchard"))
    #expect(packed.wasTruncated == false)
}

@Test("Question packing never crosses an exact character boundary")
func questionPackingHonorsExactBoundary() {
    let source = makeAskSource(pages: [
        AskPage(pageID: UUID(), plainText: "nebula nebula\n\nnebula")
    ])

    let packed = NoteAskContextPacker().packForQuestion(
        "nebula",
        source: source,
        charBudget: 22
    )

    #expect(packed.text == "[Page 1]\nnebula nebula")
    #expect(packed.text.count == 22)
    #expect(packed.text.count <= 22)
    #expect(packed.wasTruncated)
}

@Test("Question packing truncates the first relevant paragraph to fit")
func questionPackingTruncatesOversizedFirstParagraph() {
    let pageID = UUID()
    let paragraph = "quasar " + String(repeating: "filler ", count: 40)
    let source = makeAskSource(pages: [
        AskPage(pageID: pageID, plainText: paragraph)
    ])
    let charBudget = 100

    let packed = NoteAskContextPacker().packForQuestion(
        "quasar",
        source: source,
        charBudget: charBudget
    )

    #expect(!packed.text.isEmpty)
    #expect(packed.text.count <= charBudget)
    #expect(packed.wasTruncated)
    #expect(packed.includedPages.map(\.pageID).contains(pageID))
}

@Test("Equal-scoring paragraphs use page order deterministically")
func questionPackingTieBreakIsDeterministic() throws {
    let laterLexicalID = try #require(UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff"))
    let earlierLexicalID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let source = makeAskSource(pages: [
        AskPage(pageID: laterLexicalID, plainText: "quartz alpha"),
        AskPage(pageID: earlierLexicalID, plainText: "quartz beta"),
    ])
    let packer = NoteAskContextPacker()

    let first = packer.packForQuestion("quartz", source: source, charBudget: 100)
    let second = packer.packForQuestion("quartz", source: source, charBudget: 100)

    #expect(first == second)
    let pageOne = try #require(first.text.range(of: "[Page 1]"))
    let pageTwo = try #require(first.text.range(of: "[Page 2]"))
    #expect(pageOne.lowerBound < pageTwo.lowerBound)
}

@Test("Included pages preserve source order and exclude non-contributors")
func questionPackingIncludedPagesAndCompleteFlag() {
    let first = AskPage(pageID: UUID(), plainText: "Meteor appears once.")
    let second = AskPage(pageID: UUID(), plainText: "Unrelated material.")
    let third = AskPage(pageID: UUID(), plainText: "Meteor meteor appears twice.")
    let source = makeAskSource(pages: [first, second, third])

    let packed = NoteAskContextPacker().packForQuestion(
        "meteor",
        source: source,
        charBudget: 200
    )

    #expect(packed.includedPages.map(\.pageID) == [first.pageID, third.pageID])
    #expect(packed.wasTruncated == false)
}

private func makeAskSource(pages: [AskPage]) -> AskSource {
    AskSource(
        noteID: UUID(),
        title: "Test Note",
        noteType: .note,
        pages: pages
    )
}
