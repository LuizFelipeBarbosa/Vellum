import SwiftUI
import VellumCore

struct VellumGraphView: View {
    @Bindable var model: VellumAppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                let transform = VellumGraphTransform(size: geometry.size)
                ZStack {
                    Canvas { context, _ in
                        context.concatenate(CGAffineTransform(
                            a: transform.scale,
                            b: 0,
                            c: 0,
                            d: transform.scale,
                            tx: transform.xOffset,
                            ty: transform.yOffset
                        ))
                        drawGraph(in: &context)
                    }

                    if let snapshot = model.graphScreen.snapshot {
                        ForEach(snapshot.nodes) { node in
                            if let position = model.graphScreen.positions[node.id] {
                                let radius = nodeRadius(for: node)
                                Button {
                                    model.graphScreen.select(node.id)
                                } label: {
                                    Color.clear
                                        .frame(
                                            width: max(44, radius * transform.scale * 3),
                                            height: max(44, radius * transform.scale * 3)
                                        )
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .position(transform.point(x: position.x, y: position.y))
                            }
                        }
                    }

                    VStack {
                        Spacer()
                        HStack(alignment: .bottom) {
                            if let detail = model.graphScreen.selectedDetail {
                                VellumGraphInfoCard(model: model, detail: detail)
                                    .frame(width: 330)
                            }
                            Spacer()
                            VellumGraphLegend()
                        }
                        .padding(.horizontal, 26)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(VellumTheme.paper)
        .animation(.easeOut(duration: 0.2), value: model.graphScreen.selectedNodeID)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Graph")
                .font(.vellumNewsreader(24, weight: .medium))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                Text("Find a node…")
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(VellumTheme.mutedControl)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 210)
            .background(VellumTheme.ink(0.05), in: RoundedRectangle(cornerRadius: 10))
            Spacer()
            Text(model.graphScreen.headerStats + " · tap a node")
                .font(.system(size: 13))
                .foregroundStyle(VellumTheme.mutedDark)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private func drawGraph(in context: inout GraphicsContext) {
        guard let snapshot = model.graphScreen.snapshot,
              !snapshot.nodes.isEmpty else {
            let text = Text("No graph data yet")
                .font(.vellumNewsreader(17))
                .foregroundStyle(VellumTheme.muted)
            context.draw(text, at: CGPoint(x: 597, y: 350), anchor: .center)
            return
        }

        for edge in snapshot.edges {
            guard let source = model.graphScreen.positions[edge.source],
                  let target = model.graphScreen.positions[edge.target] else {
                continue
            }
            drawEdge(
                from: source,
                to: target,
                color: VellumTheme.ink(0.14),
                lineWidth: 1.2,
                context: &context
            )
        }

        if let selectedNodeID = model.graphScreen.selectedNodeID {
            for edge in snapshot.edges
            where edge.source == selectedNodeID || edge.target == selectedNodeID {
                guard let source = model.graphScreen.positions[edge.source],
                      let target = model.graphScreen.positions[edge.target] else {
                    continue
                }
                drawEdge(
                    from: source,
                    to: target,
                    color: VellumTheme.accent.opacity(0.55),
                    lineWidth: 1.6,
                    context: &context
                )
            }

            if let selectedPosition = model.graphScreen.positions[selectedNodeID] {
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: selectedPosition.x - 26,
                        y: selectedPosition.y - 26,
                        width: 52,
                        height: 52
                    )),
                    with: .color(VellumTheme.accent.opacity(0.5)),
                    lineWidth: 1.4
                )
            }
        }

        for node in snapshot.nodes {
            guard let position = model.graphScreen.positions[node.id] else { continue }
            let isSelected = node.id == model.graphScreen.selectedNodeID
            let radius: CGFloat = isSelected ? 17 : nodeRadius(for: node)
            let nodeRect = CGRect(
                x: position.x - radius,
                y: position.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: nodeRect),
                with: .color(isSelected ? VellumTheme.accent : VellumTheme.ink)
            )

            if isSelected {
                let text = Text(node.label)
                    .font(.vellumNewsreader(16, weight: .semibold))
                    .foregroundStyle(VellumTheme.ink)
                context.draw(
                    text,
                    at: CGPoint(x: position.x - 46, y: position.y + 40),
                    anchor: .bottomLeading
                )
            }
        }

        let orderedNonSelectedNodes = snapshot.nodes.enumerated()
            .filter { $0.element.id != model.graphScreen.selectedNodeID }
            .sorted { lhs, rhs in
                if lhs.element.connectionCount != rhs.element.connectionCount {
                    return lhs.element.connectionCount > rhs.element.connectionCount
                }
                if lhs.element.label != rhs.element.label {
                    return lhs.element.label < rhs.element.label
                }
                return lhs.offset < rhs.offset
            }
        var keptLabelRects: [CGRect] = []
        for (_, node) in orderedNonSelectedNodes {
            guard let position = model.graphScreen.positions[node.id] else { continue }
            let labelPoint = CGPoint(
                x: position.x + nodeRadius(for: node) + 7,
                y: position.y - 6
            )
            let text = Text(node.label)
                .font(.vellumNewsreader(14))
                .foregroundStyle(VellumTheme.bodyMuted)
            let resolvedText = context.resolve(text)
            let labelSize = resolvedText.measure(
                in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            )
            let labelRect = CGRect(
                x: labelPoint.x,
                y: labelPoint.y - labelSize.height,
                width: labelSize.width,
                height: labelSize.height
            )
            guard !keptLabelRects.contains(where: { $0.intersects(labelRect) }) else {
                continue
            }
            keptLabelRects.append(labelRect)
            context.draw(resolvedText, at: labelPoint, anchor: .bottomLeading)
        }

        for spaceNode in snapshot.nodes {
            guard case .space(let spaceID) = spaceNode.id,
                  let centroid = clusterCentroid(
                    spaceID: spaceID,
                    spaceNode: spaceNode,
                    snapshot: snapshot
                  ) else {
                continue
            }
            drawRegion(
                spaceNode.label.uppercased(),
                at: CGPoint(x: centroid.x - 56, y: centroid.y - 48),
                context: &context
            )
        }
    }

    private func drawEdge(
        from source: CGPoint,
        to target: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: source)
        path.addLine(to: target)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func nodeRadius(for node: GraphNode) -> CGFloat {
        min(6 + CGFloat(node.connectionCount) * 1.5, 17)
    }

    private func clusterCentroid(
        spaceID: UUID,
        spaceNode: GraphNode,
        snapshot: GraphSnapshot
    ) -> CGPoint? {
        var memberIDs = [spaceNode.id]
        memberIDs.append(contentsOf: snapshot.nodes.compactMap { node in
            guard node.spaceID == spaceID,
                  case .note = node.kind else {
                return nil
            }
            return node.id
        })
        let memberPositions = memberIDs.compactMap { model.graphScreen.positions[$0] }
        guard !memberPositions.isEmpty else { return nil }
        let total = memberPositions.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: total.x / CGFloat(memberPositions.count),
            y: total.y / CGFloat(memberPositions.count)
        )
    }

    private func drawRegion(_ label: String, at point: CGPoint, context: inout GraphicsContext) {
        let text = Text(label)
            .font(.system(size: 11))
            .tracking(2)
            .foregroundStyle(VellumTheme.muted)
        context.draw(text, at: point, anchor: .bottomLeading)
    }
}

private struct VellumGraphTransform {
    let scale: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat

    init(size: CGSize) {
        scale = min(size.width / 1194, size.height / 700)
        xOffset = (size.width - 1194 * scale) / 2
        yOffset = (size.height - 700 * scale) / 2
    }

    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: xOffset + x * scale, y: yOffset + y * scale)
    }
}

private struct VellumGraphInfoCard: View {
    @Bindable var model: VellumAppModel
    let detail: GraphSelectedDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(detail.label)
                    .font(.vellumNewsreader(19, weight: .semibold))
                Text(detail.kindDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(VellumTheme.muted)
            }

            VStack(spacing: 8) {
                ForEach(detail.connectedRows) { row in
                    if let noteID = row.noteID {
                        Button {
                            Task { await model.openNote(noteID) }
                        } label: {
                            connectedRow(row)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        connectedRow(row)
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(VellumTheme.bodyMuted)
            .padding(.top, 12)

            Button {
                model.askAbout("Tell me about \(detail.label)")
            } label: {
                Text("Ask about \(detail.label) →")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(VellumTheme.accentDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(VellumTheme.ink(0.08)).frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VellumTheme.ink(0.12), lineWidth: 1))
        .shadow(color: VellumTheme.ink(0.14), radius: 16, y: 10)
    }

    private func connectedRow(_ row: GraphConnectedRow) -> some View {
        HStack {
            Text(row.label)
            Spacer()
            Text(row.kindLabel).foregroundStyle(VellumTheme.mutedCount)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VellumGraphLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(VellumTheme.ink).frame(width: 8, height: 8)
                Text("source")
            }
            HStack(spacing: 6) {
                Circle().fill(VellumTheme.accent).frame(width: 11, height: 11)
                Text("selected")
            }
            Text("size = connections").foregroundStyle(VellumTheme.mutedCount)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(VellumTheme.mutedDark)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(VellumTheme.popover, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VellumTheme.ink(0.1), lineWidth: 1))
    }
}
