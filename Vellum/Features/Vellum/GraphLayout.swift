import CoreGraphics
import Foundation
import VellumCore

enum GraphLayout {
    private static let iterationCount = 200
    private static let margin: CGFloat = 60
    private static let repulsionStrength: CGFloat = 0.78
    private static let attractionStrength: CGFloat = 0.9
    private static let idealLengthScale: CGFloat = 0.74
    private static let gravityStrength: CGFloat = 0.34

    static func positions(
        nodes: [GraphNode],
        edges: [GraphEdge],
        in size: CGSize
    ) -> [GraphNodeID: CGPoint] {
        let orderedNodes = nodes.sorted { $0.id.stableGraphID < $1.id.stableGraphID }
        guard !orderedNodes.isEmpty else { return [:] }

        let width = max(size.width, margin * 2)
        let height = max(size.height, margin * 2)
        let center = CGPoint(x: width / 2, y: height / 2)
        let nodeIndices = Dictionary(
            uniqueKeysWithValues: orderedNodes.enumerated().map { ($0.element.id, $0.offset) }
        )
        let orderedEdges = indexedEdges(edges, nodeIndices: nodeIndices)
        let anchors = clusterAnchors(
            nodes: orderedNodes,
            edges: orderedEdges,
            center: center,
            size: CGSize(width: width, height: height)
        )

        let layoutSize = CGSize(width: width, height: height)
        var points = orderedNodes.map {
            initialPosition(for: $0.id, center: center, size: layoutSize)
        }
        let area = width * height
        let idealLength = sqrt(area / CGFloat(orderedNodes.count)) * idealLengthScale
        let initialTemperature = min(width, height) * 0.12

        for iteration in 0..<iterationCount {
            var displacement = Array(repeating: CGVector.zero, count: orderedNodes.count)

            for firstIndex in orderedNodes.indices {
                guard firstIndex + 1 < orderedNodes.count else { continue }
                for secondIndex in (firstIndex + 1)..<orderedNodes.count {
                    let delta = vector(from: points[secondIndex], to: points[firstIndex])
                    let distance = max(length(delta), 0.01)
                    let force = repulsionStrength * idealLength * idealLength / distance
                    let applied = scaled(delta, by: force / distance)
                    displacement[firstIndex] = displacement[firstIndex] + applied
                    displacement[secondIndex] = displacement[secondIndex] - applied
                }
            }

            for edge in orderedEdges {
                let delta = vector(from: points[edge.target], to: points[edge.source])
                let distance = max(length(delta), 0.01)
                let force = attractionStrength * distance * distance / idealLength
                let applied = scaled(delta, by: force / distance)
                displacement[edge.source] = displacement[edge.source] - applied
                displacement[edge.target] = displacement[edge.target] + applied
            }

            for index in orderedNodes.indices {
                let towardAnchor = vector(from: points[index], to: anchors[index])
                displacement[index] = displacement[index]
                    + scaled(towardAnchor, by: gravityStrength)
            }

            let progress = CGFloat(iteration) / CGFloat(max(iterationCount - 1, 1))
            let temperature = initialTemperature * pow(1 - progress, 1.35) + 0.35
            for index in orderedNodes.indices {
                let distance = max(length(displacement[index]), 0.01)
                let limited = scaled(
                    displacement[index],
                    by: min(distance, temperature) / distance
                )
                points[index].x += limited.dx
                points[index].y += limited.dy
            }
        }

        points = fitted(points, in: CGSize(width: width, height: height), margin: margin)
        var result: [GraphNodeID: CGPoint] = [:]
        result.reserveCapacity(orderedNodes.count)
        for index in orderedNodes.indices {
            result[orderedNodes[index].id] = CGPoint(
                x: clamp(points[index].x, lower: margin, upper: width - margin),
                y: clamp(points[index].y, lower: margin, upper: height - margin)
            )
        }
        return result
    }

    private struct IndexedEdge {
        let source: Int
        let target: Int
        let kind: String
    }

    private static func indexedEdges(
        _ edges: [GraphEdge],
        nodeIndices: [GraphNodeID: Int]
    ) -> [IndexedEdge] {
        edges.compactMap { edge in
            guard let source = nodeIndices[edge.source],
                  let target = nodeIndices[edge.target],
                  source != target else {
                return nil
            }
            return IndexedEdge(source: source, target: target, kind: stableDescription(edge.kind))
        }
        .sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            if lhs.target != rhs.target { return lhs.target < rhs.target }
            return lhs.kind < rhs.kind
        }
    }

    private static func clusterAnchors(
        nodes: [GraphNode],
        edges: [IndexedEdge],
        center: CGPoint,
        size: CGSize
    ) -> [CGPoint] {
        let spaceIndices = nodes.indices.filter {
            if case .space = nodes[$0].kind { return true }
            return false
        }
        let anchorRadius = min(size.width, size.height) * 0.38
        var spaceAnchors: [UUID: CGPoint] = [:]
        for (offset, nodeIndex) in spaceIndices.enumerated() {
            guard case .space(let spaceID) = nodes[nodeIndex].id else { continue }
            let fraction = CGFloat(offset) / CGFloat(max(spaceIndices.count, 1))
            let angle = -.pi / 2 + fraction * 2 * .pi
            spaceAnchors[spaceID] = CGPoint(
                x: center.x + cos(angle) * anchorRadius,
                y: center.y + sin(angle) * anchorRadius
            )
        }

        var anchors = Array(repeating: center, count: nodes.count)
        for index in nodes.indices {
            switch nodes[index].kind {
            case .space:
                if case .space(let spaceID) = nodes[index].id,
                   let anchor = spaceAnchors[spaceID] {
                    anchors[index] = anchor
                }
            case .note:
                if let spaceID = nodes[index].spaceID,
                   let anchor = spaceAnchors[spaceID] {
                    anchors[index] = anchor
                }
            case .entity:
                var connectedNoteIndices: [Int] = []
                for edge in edges where edge.kind == "entityMention" {
                    if edge.source == index, case .note = nodes[edge.target].kind {
                        connectedNoteIndices.append(edge.target)
                    } else if edge.target == index, case .note = nodes[edge.source].kind {
                        connectedNoteIndices.append(edge.source)
                    }
                }
                connectedNoteIndices.sort()
                connectedNoteIndices = deduplicated(connectedNoteIndices)

                let noteAnchors = connectedNoteIndices.map { noteIndex -> CGPoint in
                    guard let spaceID = nodes[noteIndex].spaceID else { return center }
                    return spaceAnchors[spaceID] ?? center
                }
                if !noteAnchors.isEmpty {
                    let total = noteAnchors.reduce(CGPoint.zero) { partial, point in
                        CGPoint(x: partial.x + point.x, y: partial.y + point.y)
                    }
                    anchors[index] = CGPoint(
                        x: total.x / CGFloat(noteAnchors.count),
                        y: total.y / CGFloat(noteAnchors.count)
                    )
                }
            }
        }
        return anchors
    }

    private static func initialPosition(
        for id: GraphNodeID,
        center: CGPoint,
        size: CGSize
    ) -> CGPoint {
        let stableID = id.stableGraphID
        let angleUnit = unitInterval(fnv1a64(stableID))
        let radiusUnit = unitInterval(fnv1a64("radius-\(stableID)"))
        let angle = angleUnit * 2 * .pi
        let radius = min(size.width, size.height) * (0.16 + radiusUnit * 0.24)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func unitInterval(_ value: UInt64) -> CGFloat {
        let upper53Bits = value >> 11
        return CGFloat(Double(upper53Bits) / 9_007_199_254_740_992)
    }

    private static func stableDescription(_ kind: GraphEdgeKind) -> String {
        switch kind {
        case .link(let linkKind): "link-\(linkKind.rawValue)"
        case .entityMention: "entityMention"
        case .spaceMembership: "spaceMembership"
        }
    }

    private static func deduplicated(_ values: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(values.count)
        for value in values where result.last != value {
            result.append(value)
        }
        return result
    }

    private static func vector(from source: CGPoint, to target: CGPoint) -> CGVector {
        CGVector(dx: target.x - source.x, dy: target.y - source.y)
    }

    private static func length(_ vector: CGVector) -> CGFloat {
        sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    }

    private static func scaled(_ vector: CGVector, by scalar: CGFloat) -> CGVector {
        CGVector(dx: vector.dx * scalar, dy: vector.dy * scalar)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private static func fitted(_ points: [CGPoint], in size: CGSize, margin: CGFloat) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let rangeX = max(maxX - minX, 0.01)
        let rangeY = max(maxY - minY, 0.01)
        let availableWidth = max(size.width - 2 * margin, 0.01)
        let availableHeight = max(size.height - 2 * margin, 0.01)
        let fitScale = min(1, min(availableWidth / rangeX, availableHeight / rangeY))
        let sourceCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let destinationCenter = CGPoint(x: size.width / 2, y: size.height / 2)

        return points.map { point in
            CGPoint(
                x: destinationCenter.x + (point.x - sourceCenter.x) * fitScale,
                y: destinationCenter.y + (point.y - sourceCenter.y) * fitScale
            )
        }
    }
}

extension GraphNodeID {
    var stableGraphID: String {
        switch self {
        case .note(let id): "note-\(id.uuidString)"
        case .entity(let id): "entity-\(id.uuidString)"
        case .space(let id): "space-\(id.uuidString)"
        }
    }
}

private extension CGVector {
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }
}
