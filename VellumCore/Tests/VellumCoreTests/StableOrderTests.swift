import Foundation
import Testing
@testable import VellumCore

private struct Record: Identifiable {
    let id: UUID
    let rank: Int
}

private let lowerID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
private let higherID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-0000000000FF")!

@Test("Ascending order sorts by key and breaks ties on the ascending id")
func ascendingBreaksTiesOnID() {
    let first = Record(id: higherID, rank: 1)
    let second = Record(id: lowerID, rank: 1)
    let third = Record(id: higherID, rank: 0)

    #expect(StableOrder.ascending(third, first, by: \.rank))
    #expect(!StableOrder.ascending(first, third, by: \.rank))
    #expect(StableOrder.ascending(second, first, by: \.rank))
    #expect(!StableOrder.ascending(first, second, by: \.rank))
}

@Test("Descending order reverses the key but not the tiebreak")
func descendingKeepsAscendingTiebreak() {
    let first = Record(id: higherID, rank: 1)
    let second = Record(id: lowerID, rank: 1)
    let third = Record(id: higherID, rank: 0)

    #expect(StableOrder.descending(first, third, by: \.rank))
    #expect(!StableOrder.descending(third, first, by: \.rank))
    #expect(StableOrder.descending(second, first, by: \.rank))
    #expect(!StableOrder.descending(first, second, by: \.rank))
}

@Test("An explicit tiebreak orders elements that are not identified by that key")
func explicitTiebreakOrdersUnidentifiedElements() {
    let backlinks = [
        Backlink(sourceNoteID: higherID, sourceTitle: "Same", kind: .mention),
        Backlink(sourceNoteID: lowerID, sourceTitle: "Same", kind: .related),
    ]

    let sorted = backlinks.sorted {
        StableOrder.ascending($0, $1, by: \.sourceTitle, tiebreak: \.sourceNoteID)
    }

    #expect(sorted.map(\.sourceNoteID) == [lowerID, higherID])
}
