import SwiftUI
import VellumCore

struct VellumGraphView: View {
    @Environment(\.vellumWobble) private var vellumWobble
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
                                let isSelected = node.id == model.graphScreen.selectedNodeID
                                let radius = nodeRadius(for: node, isSelected: isSelected)
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
        .background {
            VellumDotGrid(
                spacing: 22,
                dotColor: VellumTheme.ink(0.09),
                background: VellumTheme.graphBackdrop
            )
            .ignoresSafeArea()
        }
        .animation(.easeOut(duration: 0.2), value: model.graphScreen.selectedNodeID)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Graph")
                .font(.vellumSans(30, weight: .medium))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                Text("Find a node…")
                    .font(.vellumSans(15, italic: true))
                Spacer()
            }
            .foregroundStyle(VellumTheme.mutedControl)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(width: 230)
            .background {
                if vellumWobble {
                    OrganicPillShape().fill(VellumTheme.field)
                } else {
                    Capsule().fill(VellumTheme.field)
                }
            }
            .overlay {
                if vellumWobble {
                    OrganicPillShape()
                        .strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
                } else {
                    Capsule()
                        .strokeBorder(VellumTheme.ink(0.26), lineWidth: 1.5)
                }
            }
            Spacer()
            Text(model.graphScreen.headerStats + " — tap anything")
                .font(.vellumCaveat(21))
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
                .font(.vellumSans(17))
                .foregroundStyle(VellumTheme.muted)
            context.draw(text, at: CGPoint(x: 597, y: 350), anchor: .center)
            return
        }

        drawRegions(for: snapshot, context: &context)

        for (index, edge) in snapshot.edges.enumerated() {
            guard let source = model.graphScreen.positions[edge.source],
                  let target = model.graphScreen.positions[edge.target] else {
                continue
            }
            drawEdge(
                from: source,
                to: target,
                edgeIndex: index,
                color: VellumTheme.ink(0.18),
                lineWidth: 1.4,
                context: &context
            )
        }

        if let selectedNodeID = model.graphScreen.selectedNodeID {
            for (index, edge) in snapshot.edges.enumerated()
            where edge.source == selectedNodeID || edge.target == selectedNodeID {
                guard let source = model.graphScreen.positions[edge.source],
                      let target = model.graphScreen.positions[edge.target] else {
                    continue
                }
                drawEdge(
                    from: source,
                    to: target,
                    edgeIndex: index,
                    color: VellumTheme.accent.opacity(0.6),
                    lineWidth: 2.2,
                    context: &context
                )
            }
        }

        for node in snapshot.nodes {
            guard let position = model.graphScreen.positions[node.id] else { continue }
            let isSelected = node.id == model.graphScreen.selectedNodeID
            drawNode(node, at: position, isSelected: isSelected, context: &context)
        }

        drawNonSelectedLabels(for: snapshot, context: &context)
    }

    private func drawRegions(for snapshot: GraphSnapshot, context: inout GraphicsContext) {
        for spaceNode in snapshot.nodes {
            guard case .space(let spaceID) = spaceNode.id,
                  let bounds = clusterBounds(
                    spaceID: spaceID,
                    spaceNode: spaceNode,
                    snapshot: snapshot
                  ) else {
                continue
            }
            drawRegion(
                spaceNode.label.uppercased(),
                in: bounds,
                spaceID: spaceID,
                context: &context
            )
        }
    }

    private func drawEdge(
        from source: CGPoint,
        to target: CGPoint,
        edgeIndex: Int,
        color: Color,
        lineWidth: CGFloat,
        context: inout GraphicsContext
    ) {
        let deltaX = target.x - source.x
        let deltaY = target.y - source.y
        let distance = max(hypot(deltaX, deltaY), 1)
        let bend = CGFloat((edgeIndex % 3) - 1) * 14
        let midpoint = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
        let control = CGPoint(
            x: midpoint.x - deltaY / distance * bend,
            y: midpoint.y + deltaX / distance * bend
        )

        var path = Path()
        path.move(to: source)
        path.addQuadCurve(to: target, control: control)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawNode(
        _ node: GraphNode,
        at position: CGPoint,
        isSelected: Bool,
        context: inout GraphicsContext
    ) {
        let radius = nodeRadius(for: node, isSelected: isSelected)
        let nodeRect = CGRect(
            x: position.x - radius,
            y: position.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let variant = stableVariant(for: node.id.stableGraphID)

        if isSelected {
            let glowRect = nodeRect.insetBy(dx: -7, dy: -7)
            context.fill(
                blobPath(in: glowRect, variant: variant, style: .node),
                with: .color(VellumTheme.accent.opacity(0.18))
            )
            let path = blobPath(in: nodeRect, variant: variant, style: .node)
            context.fill(path, with: .color(VellumTheme.accent))
            context.stroke(path, with: .color(VellumTheme.ink), lineWidth: 2.5)

            let text = Text(node.label)
                .font(.vellumSans(19, weight: .semibold))
                .foregroundStyle(VellumTheme.ink)
            context.draw(
                text,
                at: CGPoint(x: position.x, y: position.y + radius + 10),
                anchor: .top
            )
            return
        }

        let path = blobPath(in: nodeRect, variant: variant, style: .node)
        switch node.kind {
        case .space:
            context.fill(path, with: .color(VellumTheme.ink(0.22)))
            context.stroke(
                path,
                with: .color(VellumTheme.ink(0.4)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        case .note:
            context.fill(path, with: .color(VellumTheme.ink))
        case .entity:
            context.fill(path, with: .color(VellumTheme.spaceGreen))
        }
    }

    private func drawNonSelectedLabels(
        for snapshot: GraphSnapshot,
        context: inout GraphicsContext
    ) {
        let orderedNodes = snapshot.nodes.enumerated()
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

        for (_, node) in orderedNodes {
            guard let position = model.graphScreen.positions[node.id] else { continue }
            let radius = nodeRadius(for: node, isSelected: false)
            let labelPoint = CGPoint(x: position.x + radius + 7, y: position.y - 6)
            let isSpace: Bool
            if case .space = node.kind {
                isSpace = true
            } else {
                isSpace = false
            }
            let label = isSpace ? node.label.uppercased() : node.label
            let text = Text(label)
                .font(isSpace ? .vellumMono(10.5) : .vellumSans(16))
                .tracking(isSpace ? 1.7 : 0)
                .foregroundStyle(isSpace ? VellumTheme.muted : VellumTheme.mutedDark)
            let resolvedText = context.resolve(text)
            let labelSize = resolvedText.measure(
                in: CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
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
    }

    private func nodeRadius(for node: GraphNode, isSelected: Bool) -> CGFloat {
        if isSelected {
            return 15
        }
        if case .space = node.kind {
            return 13
        }
        let diameter = min(12 + CGFloat(node.connectionCount) * 3, 38)
        return diameter / 2
    }

    private func clusterBounds(
        spaceID: UUID,
        spaceNode: GraphNode,
        snapshot: GraphSnapshot
    ) -> CGRect? {
        var memberIDs = [spaceNode.id]
        memberIDs.append(contentsOf: snapshot.nodes.compactMap { node in
            node.spaceID == spaceID ? node.id : nil
        })
        let memberPositions = memberIDs.compactMap { model.graphScreen.positions[$0] }
        guard let firstPosition = memberPositions.first else { return nil }

        var minX = firstPosition.x
        var maxX = firstPosition.x
        var minY = firstPosition.y
        var maxY = firstPosition.y
        for position in memberPositions.dropFirst() {
            minX = min(minX, position.x)
            maxX = max(maxX, position.x)
            minY = min(minY, position.y)
            maxY = max(maxY, position.y)
        }

        let padding: CGFloat = 50
        let paddedWidth = maxX - minX + padding * 2
        let paddedHeight = maxY - minY + padding * 2
        let width = max(paddedWidth, 130)
        let height = max(paddedHeight, 100)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    private func drawRegion(
        _ label: String,
        in bounds: CGRect,
        spaceID: UUID,
        context: inout GraphicsContext
    ) {
        let variant = stableVariant(for: spaceID.uuidString)
        let path = blobPath(in: bounds, variant: variant, style: .region)
        let fillColor: Color
        if let spaceColor = model.graphScreen.spaceColors[spaceID] {
            fillColor = VellumTheme.color(for: spaceColor).opacity(0.07)
        } else {
            fillColor = VellumTheme.ink(0.05)
        }
        context.fill(path, with: .color(fillColor))
        context.stroke(
            path,
            with: .color(VellumTheme.ink(0.17)),
            style: StrokeStyle(lineWidth: 1.5, dash: [8, 7], dashPhase: CGFloat(variant) * 2)
        )

        let text = Text(label)
            .font(.vellumMono(10.5))
            .tracking(1.7)
            .foregroundStyle(VellumTheme.muted)
        context.draw(
            text,
            at: CGPoint(x: bounds.minX + 18, y: bounds.minY + 14),
            anchor: .topLeading
        )
    }

    private func blobPath(in rect: CGRect, variant: Int, style: GraphBlobStyle) -> Path {
        let radiusBasis = min(rect.width, rect.height)
        let baseRadii: [CGFloat]
        if vellumWobble {
            switch style {
            case .region:
                baseRadii = [0.42, 0.18, 0.36, 0.24]
            case .node:
                baseRadii = [0.60, 0.40, 0.55, 0.45]
            }
        } else {
            let radius = style == .region ? min(22 / radiusBasis, 0.22) : 0.5
            baseRadii = Array(repeating: radius, count: 4)
        }

        let rotation = ((variant % 4) + 4) % 4
        let radii = (0..<4).map { index in
            baseRadii[(index + rotation) % 4] * radiusBasis
        }
        let corners = RectangleCornerRadii(
            topLeading: radii[0],
            bottomLeading: radii[3],
            bottomTrailing: radii[2],
            topTrailing: radii[1]
        )
        return UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
            .path(in: rect)
    }

    private func stableVariant(for value: String) -> Int {
        value.utf8.reduce(0) { partial, byte in
            (partial * 31 + Int(byte)) % 4
        }
    }
}

private enum GraphBlobStyle: Equatable {
    case region
    case node
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
                    .font(.vellumSans(24, weight: .semibold))
                Text(detail.kindDescription)
                    .font(.vellumMono(10.5))
                    .foregroundStyle(VellumTheme.muted)
            }

            VStack(spacing: 0) {
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
            .foregroundStyle(VellumTheme.bodyMuted)
            .padding(.top, 10)

            Button {
                model.askAbout("Tell me about \(detail.label)")
            } label: {
                Text("ask about \(detail.label) →")
                    .font(.vellumSans(14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VellumPillButtonStyle(.primary))
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .vellumFloatingChrome(.panel)
    }

    private func connectedRow(_ row: GraphConnectedRow) -> some View {
        HStack(spacing: 12) {
            Text(row.label)
                .font(.vellumSans(14))
            Spacer(minLength: 8)
            Text(row.kindLabel)
                .font(.vellumMono(10.5))
                .foregroundStyle(VellumTheme.mutedCount)
                .frame(width: 76, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct VellumGraphLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                VellumBlobDot(color: VellumTheme.ink, size: 9)
                Text("note")
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(VellumTheme.spaceGreen)
                    .frame(width: 8, height: 8)
                Text("person / topic")
            }
            HStack(spacing: 6) {
                VellumBlobDot(color: VellumTheme.accent, size: 11)
                Text("selected")
            }
            Text("size = links")
                .foregroundStyle(VellumTheme.mutedCount)
        }
        .font(.vellumMono(11))
        .foregroundStyle(VellumTheme.mutedDark)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .vellumFloatingChrome(.panel)
    }
}
