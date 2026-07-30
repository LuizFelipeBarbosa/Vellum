import SwiftUI
import VellumCore

enum SelectionHandleGeometry {
    static let resizeHitSize: CGFloat = 28
    static let rotationHitSize: CGFloat = 32
    static let rotationOffset: CGFloat = 28

    /// Snapping the combined orientation makes cardinal targets reachable from elements that
    /// already have a committed rotation while still returning the live delta the controller owns.
    static func snappedRotation(committed: Double, delta: Double) -> Double {
        let fullTurn = Double.pi * 2
        let total = committed + delta
        var normalizedTotal = total.truncatingRemainder(dividingBy: fullTurn)
        if normalizedTotal < 0 {
            normalizedTotal += fullTurn
        }

        let snapPoints = stride(from: 0.0, through: fullTurn, by: Double.pi / 2)
        let nearest = snapPoints.min { lhs, rhs in
            abs(normalizedTotal - lhs) < abs(normalizedTotal - rhs)
        }
        if let nearest, abs(normalizedTotal - nearest) <= 4 * .pi / 180 {
            return nearest - committed
        }
        return normalizedTotal - committed
    }
}

enum SelectionHandle: CaseIterable, Hashable, Identifiable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
    case rotation

    static let resizeHandles: [SelectionHandle] = [
        .topLeft,
        .top,
        .topRight,
        .left,
        .right,
        .bottomLeft,
        .bottom,
        .bottomRight,
    ]

    var id: Self { self }

    var unitPoint: CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: 0, y: 0)
        case .top, .rotation:
            CGPoint(x: 0.5, y: 0)
        case .topRight:
            CGPoint(x: 1, y: 0)
        case .left:
            CGPoint(x: 0, y: 0.5)
        case .right:
            CGPoint(x: 1, y: 0.5)
        case .bottomLeft:
            CGPoint(x: 0, y: 1)
        case .bottom:
            CGPoint(x: 0.5, y: 1)
        case .bottomRight:
            CGPoint(x: 1, y: 1)
        }
    }

    var anchorUnit: CGPoint {
        switch self {
        case .rotation:
            SelectionResizeMath.centerUnit
        default:
            SelectionResizeMath.oppositeUnit(of: unitPoint)
        }
    }

    func anchorPoint(in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: bounds.minX + unitPoint.x * bounds.width,
            y: bounds.minY + unitPoint.y * bounds.height
        )
    }

    var accessibilityLabel: String {
        switch self {
        case .topLeft:
            "Resize handle, top left corner"
        case .top:
            "Resize handle, top edge"
        case .topRight:
            "Resize handle, top right corner"
        case .left:
            "Resize handle, left edge"
        case .right:
            "Resize handle, right edge"
        case .bottomLeft:
            "Resize handle, bottom left corner"
        case .bottom:
            "Resize handle, bottom edge"
        case .bottomRight:
            "Resize handle, bottom right corner"
        case .rotation:
            "Rotate selection"
        }
    }
}

struct SelectionOverlayView: View {
    let controller: CanvasSelectionController
    let selectionMode: SelectionMode
    let isActive: Bool
    let isSelectToolActive: Bool

    @State private var activeHandle: SelectionHandle?
    @State private var activeVertexIndex: Int?

    private static let coordinateSpaceName = "vellum-selection-overlay"

    var body: some View {
        Group {
            if isActive {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        captureSurface

                        if let snapshot = controller.strokesSnapshot,
                           let bounds = controller.selectionBounds {
                            selectionSnapshot(snapshot, in: bounds)
                        }

                        if let bounds = controller.selectionBounds,
                           controller.selection != nil {
                            selectionOutline(in: bounds)

                            if controller.capturePath == nil,
                               controller.strokesSnapshot == nil
                                || controller.isHandleDragging {
                                let shape = controller.vertexEditableElement()

                                if !controller.isVertexDragging {
                                    // A shape carries its own handles, which sit on the curve or
                                    // the vertices — right where the frame's resize handles would
                                    // be. Showing both stacks two grabbable targets on the same
                                    // point, so the frame's give way and only rotation remains.
                                    selectionHandles(
                                        in: bounds,
                                        includesResizeHandles: shape == nil
                                            || controller.isHandleDragging
                                    )
                                }

                                if !controller.isHandleDragging, let shape {
                                    vertexHandles(for: shape)
                                }
                            }
                        }

                        if let capturePath = controller.capturePath {
                            capturePath
                                .stroke(
                                    VellumTheme.accentDark,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(name: Self.coordinateSpaceName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
    }

    private var captureSurface: some View {
        SelectionCaptureSurface(
            controller: controller,
            selectionMode: selectionMode,
            isEnabled: isSelectToolActive
        )
        .allowsHitTesting(false)
        .accessibilityLabel("Canvas selection area")
    }

    // The geometry effects below do not drive hit testing: both chrome views are non-interactive,
    // while the handles use real layout positions from livePoint.
    @ViewBuilder
    private func selectionSnapshot(_ snapshot: UIImage, in bounds: CGRect) -> some View {
        let localBounds = CGRect(origin: .zero, size: bounds.size)
        let framed = Image(uiImage: snapshot)
            .resizable()
            .frame(width: bounds.width, height: bounds.height)

        if controller.isHandleDragging {
            framed
                // Snapshot pixels already contain committed rotation, so use the interaction
                // transform; chromeTransform would rotate that baked orientation a second time.
                .transformEffect(
                    SelectionResizeMath.transform(
                        bounds: localBounds,
                        anchorUnit: controller.handleAnchor,
                        scale: controller.handleScale,
                        rotationDelta: controller.handleRotation,
                        committedRotation: controller.committedChromeRotation
                    )
                )
                .position(x: bounds.midX, y: bounds.midY)
                .opacity(0.9)
                .allowsHitTesting(false)
        } else {
            framed
                .transformEffect(
                    SelectionResizeMath.transform(
                        bounds: localBounds,
                        anchorUnit: SelectionResizeMath.centerUnit,
                        scale: CGSize(width: 1, height: 1),
                        rotationDelta: 0,
                        committedRotation: controller.committedChromeRotation
                    )
                )
                .position(x: bounds.midX, y: bounds.midY)
                .offset(controller.dragTranslation)
                .opacity(0.9)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func selectionOutline(in bounds: CGRect) -> some View {
        let localBounds = CGRect(origin: .zero, size: bounds.size)
        let framed = RoundedRectangle(cornerRadius: 8)
            .stroke(
                VellumTheme.accentDark,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
            .frame(width: bounds.width, height: bounds.height)

        if controller.isHandleDragging {
            framed
                // The outline starts unrotated, unlike the snapshot, so chromeTransform supplies
                // both the committed orientation and the shared anchored interaction transform.
                .transformEffect(
                    SelectionResizeMath.chromeTransform(
                        bounds: localBounds,
                        anchorUnit: controller.handleAnchor,
                        scale: controller.handleScale,
                        rotationDelta: controller.handleRotation,
                        committedRotation: controller.committedChromeRotation
                    )
                )
                .position(x: bounds.midX, y: bounds.midY)
                .allowsHitTesting(false)
        } else {
            framed
                .transformEffect(
                    SelectionResizeMath.chromeTransform(
                        bounds: localBounds,
                        anchorUnit: SelectionResizeMath.centerUnit,
                        scale: CGSize(width: 1, height: 1),
                        rotationDelta: 0,
                        committedRotation: controller.committedChromeRotation
                    )
                )
                .position(x: bounds.midX, y: bounds.midY)
                .offset(controller.dragTranslation)
                .allowsHitTesting(false)
        }
    }

    private func selectionHandles(
        in bounds: CGRect,
        includesResizeHandles: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: livePoint(for: .top, in: bounds))
                path.addLine(to: livePoint(for: .rotation, in: bounds))
            }
            .stroke(VellumTheme.accentDark, lineWidth: 1.5)
            .allowsHitTesting(false)

            ForEach(includesResizeHandles ? SelectionHandle.resizeHandles : []) { handle in
                Rectangle()
                    .fill(VellumTheme.popover)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Rectangle()
                            .stroke(VellumTheme.accentDark, lineWidth: 1.5)
                    }
                    .frame(
                        width: SelectionHandleGeometry.resizeHitSize,
                        height: SelectionHandleGeometry.resizeHitSize
                    )
                    .contentShape(Rectangle())
                    .position(livePoint(for: handle, in: bounds))
                    .gesture(handleGesture(handle, bounds: bounds))
                    .accessibilityLabel(handle.accessibilityLabel)
            }

            Circle()
                .fill(VellumTheme.popover)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(VellumTheme.accentDark, lineWidth: 1.5)
                }
                .frame(
                    width: SelectionHandleGeometry.rotationHitSize,
                    height: SelectionHandleGeometry.rotationHitSize
                )
                .contentShape(Circle())
                .position(livePoint(for: .rotation, in: bounds))
                .gesture(handleGesture(.rotation, bounds: bounds))
                .accessibilityLabel(SelectionHandle.rotation.accessibilityLabel)
        }
    }

    private func vertexHandles(for element: CanvasElement) -> some View {
        let vertices = controller.vertexEditHandles(for: element)

        return ZStack(alignment: .topLeading) {
            ForEach(Array(vertices.enumerated()), id: \.offset) { index, vertex in
                Circle()
                    .fill(VellumTheme.accentDark)
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle()
                            .stroke(VellumTheme.popover, lineWidth: 1.5)
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                    .position(vertex)
                    .gesture(
                        vertexGesture(
                            elementID: element.id,
                            vertexIndex: index
                        )
                    )
                    .accessibilityLabel("Shape vertex handle")
                    .accessibilityIdentifier("vellum-shape-vertex-handle-\(index)")
            }
        }
        // Swapping the selected shape under an in-flight drag cancels the gesture, and the
        // handles going away does the same; either way `.onEnded` never runs.
        .onChange(of: element.id) { _, _ in
            releaseStrandedVertexDrag()
        }
        .onDisappear {
            releaseStrandedVertexDrag()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shape vertex handles")
        .accessibilityIdentifier("vellum-shape-vertex-handles")
        .accessibilityValue(vertexSummary(vertices))
    }

    private func vertexGesture(
        elementID: UUID,
        vertexIndex: Int
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                // A cancelled gesture never reports `.onEnded`, so `activeVertexIndex` can
                // outlive its drag. Rather than dead-end every other handle, let a fresh touch
                // take the drag over — `beginVertexDrag` drops whatever was still in flight.
                if activeVertexIndex != vertexIndex {
                    activeVertexIndex = vertexIndex
                    controller.beginVertexDrag(
                        elementID: elementID,
                        vertexIndex: vertexIndex
                    )
                }
                controller.setVertexPosition(value.location)
            }
            .onEnded { _ in
                guard activeVertexIndex == vertexIndex else { return }
                controller.endVertexDrag()
                activeVertexIndex = nil
            }
    }

    /// Lets go of a drag SwiftUI cancelled: without this the stale index blocks every other
    /// handle and the controller stays in its dragging state, which hides the rotation handle
    /// for good. `endVertexDrag` commits whatever the drag already wrote and is a no-op when
    /// no drag is in flight.
    private func releaseStrandedVertexDrag() {
        activeVertexIndex = nil
        controller.endVertexDrag()
    }

    private func vertexSummary(_ vertices: [CGPoint]) -> String {
        vertices.map { "\($0.x),\($0.y)" }.joined(separator: ";")
    }

    private func handleGesture(
        _ handle: SelectionHandle,
        bounds: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if activeHandle == nil {
                    activeHandle = handle
                    controller.beginHandleDrag()
                }
                guard activeHandle == handle else { return }

                let transform = handleTransform(
                    for: handle,
                    bounds: bounds,
                    start: value.startLocation,
                    current: value.location
                )
                controller.setHandleTransform(
                    scale: transform.scale,
                    rotation: transform.rotation,
                    anchor: transform.anchor
                )
            }
            .onEnded { _ in
                guard activeHandle == handle else { return }
                controller.endHandleDrag()
                activeHandle = nil
            }
    }

    private func handleTransform(
        for handle: SelectionHandle,
        bounds: CGRect,
        start: CGPoint,
        current: CGPoint
    ) -> (scale: CGSize, rotation: Double, anchor: CGPoint) {
        let committedRotation = controller.committedChromeRotation

        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let factor = SelectionResizeMath.cornerFactor(
                handleUnit: handle.unitPoint,
                anchorUnit: handle.anchorUnit,
                bounds: bounds,
                rotation: committedRotation,
                current: current
            )
            let scale = SelectionResizeMath.clampedScale(
                CGSize(width: factor, height: factor),
                in: bounds,
                uniform: true
            )
            return (scale, 0, handle.anchorUnit)
        case .left, .right:
            let factor = SelectionResizeMath.edgeFactor(
                handleUnit: handle.unitPoint,
                anchorUnit: handle.anchorUnit,
                bounds: bounds,
                rotation: committedRotation,
                current: current,
                axisIsX: true
            )
            let scale = SelectionResizeMath.clampedScale(
                CGSize(width: factor, height: 1),
                in: bounds,
                uniform: false
            )
            return (scale, 0, handle.anchorUnit)
        case .top, .bottom:
            let factor = SelectionResizeMath.edgeFactor(
                handleUnit: handle.unitPoint,
                anchorUnit: handle.anchorUnit,
                bounds: bounds,
                rotation: committedRotation,
                current: current,
                axisIsX: false
            )
            let scale = SelectionResizeMath.clampedScale(
                CGSize(width: 1, height: factor),
                in: bounds,
                uniform: false
            )
            return (scale, 0, handle.anchorUnit)
        case .rotation:
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            return (
                CGSize(width: 1, height: 1),
                snappedRotation(Double(currentAngle - startAngle)),
                SelectionResizeMath.centerUnit
            )
        }
    }

    private func snappedRotation(_ rotation: Double) -> Double {
        SelectionHandleGeometry.snappedRotation(
            committed: controller.committedChromeRotation,
            delta: rotation
        )
    }

    private func livePoint(for handle: SelectionHandle, in bounds: CGRect) -> CGPoint {
        let isDragging = controller.isHandleDragging
        let scale = isDragging
            ? controller.handleScale
            : CGSize(width: 1, height: 1)
        let anchorUnit = isDragging
            ? controller.handleAnchor
            : SelectionResizeMath.centerUnit
        let rotationDelta = isDragging ? controller.handleRotation : 0
        let committedRotation = controller.committedChromeRotation
        let transformedPoint = SelectionResizeMath.point(
            atUnit: handle.unitPoint,
            in: bounds,
            rotation: 0
        ).applying(
            SelectionResizeMath.chromeTransform(
                bounds: bounds,
                anchorUnit: anchorUnit,
                scale: scale,
                rotationDelta: rotationDelta,
                committedRotation: committedRotation
            )
        )
        if handle == .rotation {
            let rotation = committedRotation + rotationDelta
            return CGPoint(
                x: transformedPoint.x
                    + CGFloat(sin(rotation)) * SelectionHandleGeometry.rotationOffset,
                y: transformedPoint.y
                    - CGFloat(cos(rotation)) * SelectionHandleGeometry.rotationOffset
            )
        }
        return transformedPoint
    }
}
