import CoreGraphics
import Foundation

public enum PageTextAssembler {
    public static func assemble(
        inkLines: [RecognizedLine],
        pages: [NotePage],
        geometry: PageGeometry
    ) -> [RecognizedPageText] {
        guard !pages.isEmpty else { return [] }

        let typedLines = pages[0].elements.compactMap { element -> RecognizedLine? in
            guard case .text(let box) = element.content else { return nil }
            guard !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return RecognizedLine(
                text: box.text,
                rect: element.frame,
                confidence: 1,
                source: .typed
            )
        }

        var linesByBand = Array(repeating: [RecognizedLine](), count: pages.count)
        for line in inkLines + typedLines {
            let band = PageBandAssignment.band(
                forAnchorY: CGFloat(line.rect.y + line.rect.height / 2),
                bandCount: pages.count,
                geometry: geometry
            )
            linesByBand[band].append(line)
        }

        return pages.enumerated().map { bandIndex, page in
            let sortedLines = linesByBand[bandIndex].sorted { lhs, rhs in
                if lhs.rect.y == rhs.rect.y {
                    return lhs.rect.x < rhs.rect.x
                }
                return lhs.rect.y < rhs.rect.y
            }
            return RecognizedPageText(
                pageID: page.id,
                pageIndex: bandIndex,
                lines: sortedLines,
                plainText: sortedLines.map(\.text).joined(separator: "\n")
            )
        }
    }
}
