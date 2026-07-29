import CoreGraphics
import Foundation
import VellumCore

enum ReorderDirection: String, CaseIterable, Sendable {
    case toFront
    case forward
    case backward
    case toBack

    var undoLabel: String {
        switch self {
        case .toFront:
            "Bring to Front"
        case .forward:
            "Bring Forward"
        case .backward:
            "Send Backward"
        case .toBack:
            "Send to Back"
        }
    }
}

enum ElementReorderer {
    /// Returns the new full elements array, or nil when the operation is a visual no-op.
    /// A successful reorder materializes every placement so later legacy normalization cannot
    /// reinterpret the explicit order.
    static func reorder(
        elements: [CanvasElement],
        selectedIDs: Set<UUID>,
        direction: ReorderDirection,
        inkRects: [CGRect]
    ) -> [CanvasElement]? {
        guard let context = ReorderContext(
            elements: elements,
            selectedIDs: selectedIDs
        ) else {
            return nil
        }

        switch direction {
        case .toFront:
            let isTopmost = context.sequence.suffix(context.selected.count).map(\.id)
                == context.selected.map(\.id)
            let allAboveInk = context.selected.allSatisfy {
                $0.effectivePlacement == .aboveInk
            }
            guard !(isTopmost && allAboveInk) else {
                return nil
            }
            return result(
                from: context,
                placement: .aboveInk,
                insertionIndex: context.rest.count
            )
        case .forward:
            return moveForward(
                context,
                inkIntersectsSelection: inkRects.contains {
                    $0.intersects(context.selectedBounds)
                }
            )
        case .backward:
            return moveBackward(
                context,
                inkIntersectsSelection: inkRects.contains {
                    $0.intersects(context.selectedBounds)
                }
            )
        case .toBack:
            let isBottommost = context.sequence.prefix(context.selected.count).map(\.id)
                == context.selected.map(\.id)
            let allBelowInk = context.selected.allSatisfy {
                $0.effectivePlacement == .belowInk
            }
            guard !(isBottommost && allBelowInk) else {
                return nil
            }
            return result(
                from: context,
                placement: .belowInk,
                insertionIndex: 0
            )
        }
    }

    private static func moveForward(
        _ context: ReorderContext,
        inkIntersectsSelection: Bool
    ) -> [CanvasElement]? {
        let candidate: CanvasElement?
        if context.topmostSelectedIndex < context.belowCount {
            candidate = firstCandidate(
                in: context.sequence,
                indices: (context.topmostSelectedIndex + 1)..<context.belowCount,
                selectedBounds: context.selectedBounds,
                ascending: true
            )
            if candidate == nil, inkIntersectsSelection {
                return result(
                    from: context,
                    placement: .aboveInk,
                    insertionIndex: context.restBelowCount
                )
            }
            if candidate == nil {
                return moveForwardToCandidate(
                    firstCandidate(
                        in: context.sequence,
                        indices: context.belowCount..<context.sequence.count,
                        selectedBounds: context.selectedBounds,
                        ascending: true
                    ),
                    context: context
                )
            }
        } else {
            candidate = firstCandidate(
                in: context.sequence,
                indices: (context.topmostSelectedIndex + 1)..<context.sequence.count,
                selectedBounds: context.selectedBounds,
                ascending: true
            )
        }

        return moveForwardToCandidate(candidate, context: context)
    }

    private static func moveForwardToCandidate(
        _ candidate: CanvasElement?,
        context: ReorderContext
    ) -> [CanvasElement]? {
        guard let candidate,
              let candidateIndex = context.rest.firstIndex(where: {
                  $0.id == candidate.id
              }) else {
            return nil
        }
        return result(
            from: context,
            placement: candidate.effectivePlacement,
            insertionIndex: candidateIndex + 1
        )
    }

    private static func moveBackward(
        _ context: ReorderContext,
        inkIntersectsSelection: Bool
    ) -> [CanvasElement]? {
        let candidate: CanvasElement?
        if context.bottommostSelectedIndex >= context.belowCount {
            candidate = firstCandidate(
                in: context.sequence,
                indices: context.belowCount..<context.bottommostSelectedIndex,
                selectedBounds: context.selectedBounds,
                ascending: false
            )
            if candidate == nil, inkIntersectsSelection {
                return result(
                    from: context,
                    placement: .belowInk,
                    insertionIndex: context.restBelowCount
                )
            }
            if candidate == nil {
                return moveBackwardToCandidate(
                    firstCandidate(
                        in: context.sequence,
                        indices: 0..<context.belowCount,
                        selectedBounds: context.selectedBounds,
                        ascending: false
                    ),
                    context: context
                )
            }
        } else {
            candidate = firstCandidate(
                in: context.sequence,
                indices: 0..<context.bottommostSelectedIndex,
                selectedBounds: context.selectedBounds,
                ascending: false
            )
        }

        return moveBackwardToCandidate(candidate, context: context)
    }

    private static func moveBackwardToCandidate(
        _ candidate: CanvasElement?,
        context: ReorderContext
    ) -> [CanvasElement]? {
        guard let candidate,
              let candidateIndex = context.rest.firstIndex(where: {
                  $0.id == candidate.id
              }) else {
            return nil
        }
        return result(
            from: context,
            placement: candidate.effectivePlacement,
            insertionIndex: candidateIndex
        )
    }

    private static func firstCandidate(
        in sequence: [CanvasElement],
        indices: Range<Int>,
        selectedBounds: CGRect,
        ascending: Bool
    ) -> CanvasElement? {
        if ascending {
            for index in indices
            where sequence[index].rotatedBoundingBox.intersects(selectedBounds) {
                return sequence[index]
            }
        } else {
            for index in indices.reversed()
            where sequence[index].rotatedBoundingBox.intersects(selectedBounds) {
                return sequence[index]
            }
        }
        return nil
    }

    private static func result(
        from context: ReorderContext,
        placement: LayerPlacement,
        insertionIndex: Int
    ) -> [CanvasElement] {
        let moved = context.selected.map { element in
            var element = element
            element.layerPlacement = placement
            return element
        }
        var reordered = context.rest
        reordered.insert(contentsOf: moved, at: insertionIndex)

        return reordered.map { element in
            var element = element
            element.layerPlacement = element.effectivePlacement
            return element
        }
    }

    private struct ReorderContext {
        let sequence: [CanvasElement]
        let selected: [CanvasElement]
        let rest: [CanvasElement]
        let belowCount: Int
        let restBelowCount: Int
        let selectedBounds: CGRect
        let bottommostSelectedIndex: Int
        let topmostSelectedIndex: Int

        init?(elements: [CanvasElement], selectedIDs: Set<UUID>) {
            let normalized = elements.zOrderNormalized()
            let below = normalized.filter { $0.effectivePlacement == .belowInk }
            let above = normalized.filter { $0.effectivePlacement == .aboveInk }
            let sequence = below + above
            let selectedIndices = sequence.indices.filter {
                selectedIDs.contains(sequence[$0].id)
            }
            guard let bottommostSelectedIndex = selectedIndices.first,
                  let topmostSelectedIndex = selectedIndices.last else {
                return nil
            }

            let selected = selectedIndices.map { sequence[$0] }
            let selectedIDSet = Set(selected.map(\.id))
            let rest = sequence.filter { !selectedIDSet.contains($0.id) }
            let firstBounds = selected[0].rotatedBoundingBox

            self.sequence = sequence
            self.selected = selected
            self.rest = rest
            belowCount = below.count
            restBelowCount = rest.filter {
                $0.effectivePlacement == .belowInk
            }.count
            selectedBounds = selected.dropFirst().reduce(firstBounds) {
                $0.union($1.rotatedBoundingBox)
            }
            self.bottommostSelectedIndex = bottommostSelectedIndex
            self.topmostSelectedIndex = topmostSelectedIndex
        }
    }
}
