import CoreGraphics
import Foundation
import Observation
import VellumCore

struct GraphConnectedRow: Identifiable {
    let id: GraphNodeID
    let label: String
    let kindLabel: String
    let isNote: Bool
    let noteID: UUID?
}

struct GraphSelectedDetail {
    let label: String
    let kindDescription: String
    let connectedRows: [GraphConnectedRow]
    let isNote: Bool
    let selectedNoteID: UUID?
}

@MainActor
@Observable
final class GraphScreenModel {
    private let container: AppContainer

    var snapshot: GraphSnapshot?
    var positions: [GraphNodeID: CGPoint] = [:]
    var selectedNodeID: GraphNodeID?

    init(container: AppContainer) {
        self.container = container
    }

    func refresh() async {
        guard let refreshedSnapshot = try? await container.graph.snapshot() else { return }
        snapshot = refreshedSnapshot
        positions = GraphLayout.positions(
            nodes: refreshedSnapshot.nodes,
            edges: refreshedSnapshot.edges,
            in: CGSize(width: 1194, height: 700)
        )

        let availableIDs = Set(refreshedSnapshot.nodes.map(\.id))
        if selectedNodeID.map({ availableIDs.contains($0) }) != true {
            selectedNodeID = refreshedSnapshot.nodes.sorted { lhs, rhs in
                if lhs.connectionCount != rhs.connectionCount {
                    return lhs.connectionCount > rhs.connectionCount
                }
                return lhs.id.stableGraphID < rhs.id.stableGraphID
            }.first?.id
        }
    }

    func select(_ id: GraphNodeID) {
        selectedNodeID = id
    }

    func selectEntity(named name: String) {
        guard let entityNode = snapshot?.nodes.first(where: { node in
            guard case .entity = node.kind else { return false }
            return node.label == name
        }) else {
            return
        }
        selectedNodeID = entityNode.id
    }

    var selectedDetail: GraphSelectedDetail? {
        guard let snapshot,
              let selectedNodeID,
              let selectedNode = snapshot.nodes.first(where: { $0.id == selectedNodeID }) else {
            return nil
        }

        let nodesByID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        var connectedIDs: [GraphNodeID] = []
        for edge in snapshot.edges {
            if edge.source == selectedNodeID, edge.target != selectedNodeID {
                connectedIDs.append(edge.target)
            } else if edge.target == selectedNodeID, edge.source != selectedNodeID {
                connectedIDs.append(edge.source)
            }
        }
        connectedIDs.sort { $0.stableGraphID < $1.stableGraphID }

        var uniqueConnectedIDs: [GraphNodeID] = []
        for id in connectedIDs where uniqueConnectedIDs.last != id {
            uniqueConnectedIDs.append(id)
        }

        let rows = uniqueConnectedIDs.compactMap { id -> GraphConnectedRow? in
            guard let node = nodesByID[id] else { return nil }
            let noteID: UUID?
            if case .note(let id) = node.id {
                noteID = id
            } else {
                noteID = nil
            }
            return GraphConnectedRow(
                id: node.id,
                label: node.label,
                kindLabel: kindLabel(for: node.kind),
                isNote: noteID != nil,
                noteID: noteID
            )
        }
        .sorted { lhs, rhs in
            let labelComparison = lhs.label.caseInsensitiveCompare(rhs.label)
            if labelComparison != .orderedSame {
                return labelComparison == .orderedAscending
            }
            return lhs.id.stableGraphID < rhs.id.stableGraphID
        }

        let selectedNoteID: UUID?
        if case .note(let id) = selectedNode.id {
            selectedNoteID = id
        } else {
            selectedNoteID = nil
        }

        return GraphSelectedDetail(
            label: selectedNode.label,
            kindDescription: detailDescription(for: selectedNode),
            connectedRows: rows,
            isNote: selectedNoteID != nil,
            selectedNoteID: selectedNoteID
        )
    }

    var headerStats: String {
        "\(snapshot?.nodes.count ?? 0) nodes · \(snapshot?.edges.count ?? 0) links"
    }

    private func detailDescription(for node: GraphNode) -> String {
        switch node.kind {
        case .note:
            "note · \(node.connectionCount) links"
        case .entity(let kind):
            "\(kind.rawValue) · \(node.connectionCount) sources"
        case .space:
            "space · \(node.connectionCount) sources"
        }
    }

    private func kindLabel(for kind: GraphNodeKind) -> String {
        switch kind {
        case .note: "note"
        case .entity(let entityKind): entityKind.rawValue
        case .space: "space"
        }
    }
}
