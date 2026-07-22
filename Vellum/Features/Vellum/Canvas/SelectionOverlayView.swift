import SwiftUI

struct SelectionOverlayView: View {
    let controller: CanvasSelectionController
    let selectionMode: SelectionMode
    let isActive: Bool

    @State private var activeHandle: SelectionHandle?

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
                                selectionHandles(in: bounds)
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
        SelectionCaptureSurface(controller: controller, selectionMode: selectionMode)
            .allowsHitTesting(false)
            .accessibilityLabel("Canvas selection area")
    }

    @ViewBuilder
    private func selectionSnapshot(_ snapshot: UIImage, in bounds: CGRect) -> some View {
        let framed = Image(uiImage: snapshot)
            .resizable()
            .frame(width: bounds.width, height: bounds.height)

        if controller.isHandleDragging {
            framed
                .scaleEffect(controller.handleScale)
                .rotationEffect(.radians(controller.handleRotation))
                .position(x: bounds.midX, y: bounds.midY)
                .opacity(0.9)
                .allowsHitTesting(false)
        } else {
            framed
                .scaleEffect(CGSize(width: 1, height: 1))
                .rotationEffect(.radians(0))
                .position(x: bounds.midX, y: bounds.midY)
                .offset(controller.dragTranslation)
                .opacity(0.9)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func selectionOutline(in bounds: CGRect) -> some View {
        let framed = RoundedRectangle(cornerRadius: 8)
            .stroke(
                VellumTheme.accentDark,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
            .frame(width: bounds.width, height: bounds.height)

        if controller.isHandleDragging {
            framed
                .scaleEffect(controller.handleScale)
                .rotationEffect(.radians(controller.handleRotation))
                .position(x: bounds.midX, y: bounds.midY)
                .allowsHitTesting(false)
        } else {
            framed
                .scaleEffect(CGSize(width: 1, height: 1))
                .rotationEffect(.radians(0))
                .position(x: bounds.midX, y: bounds.midY)
                .offset(controller.dragTranslation)
                .allowsHitTesting(false)
        }
    }

    private func selectionHandles(in bounds: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: livePoint(for: .top, in: bounds))
                path.addLine(to: livePoint(for: .rotation, in: bounds))
            }
            .stroke(VellumTheme.accentDark, lineWidth: 1.5)
            .allowsHitTesting(false)

            ForEach(SelectionHandle.resizeHandles) { handle in
                Rectangle()
                    .fill(VellumTheme.popover)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Rectangle()
                            .stroke(VellumTheme.accentDark, lineWidth: 1.5)
                    }
                    .frame(width: 28, height: 28)
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
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .position(livePoint(for: .rotation, in: bounds))
                .gesture(handleGesture(.rotation, bounds: bounds))
                .accessibilityLabel(SelectionHandle.rotation.accessibilityLabel)
        }
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
                    rotation: transform.rotation
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
    ) -> (scale: CGSize, rotation: Double) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let original = handle.anchorPoint(in: bounds)
            let originalDistance = hypot(original.x - center.x, original.y - center.y)
            let currentDistance = hypot(current.x - center.x, current.y - center.y)
            let factor = originalDistance > 0 ? currentDistance / originalDistance : 1
            return (CGSize(width: factor, height: factor), 0)
        case .left, .right:
            let halfWidth = bounds.width / 2
            let factor = halfWidth > 0 ? abs(current.x - center.x) / halfWidth : 1
            return (CGSize(width: factor, height: 1), 0)
        case .top, .bottom:
            let halfHeight = bounds.height / 2
            let factor = halfHeight > 0 ? abs(current.y - center.y) / halfHeight : 1
            return (CGSize(width: 1, height: factor), 0)
        case .rotation:
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            return (
                CGSize(width: 1, height: 1),
                snappedRotation(Double(currentAngle - startAngle))
            )
        }
    }

    private func snappedRotation(_ rotation: Double) -> Double {
        let fullTurn = Double.pi * 2
        var normalized = rotation.truncatingRemainder(dividingBy: fullTurn)
        if normalized < 0 {
            normalized += fullTurn
        }

        let snapPoints = stride(from: 0.0, through: fullTurn, by: Double.pi / 2)
        let nearest = snapPoints.min { lhs, rhs in
            abs(normalized - lhs) < abs(normalized - rhs)
        }
        if let nearest, abs(normalized - nearest) <= 4 * .pi / 180 {
            return nearest
        }
        return normalized
    }

    private func livePoint(for handle: SelectionHandle, in bounds: CGRect) -> CGPoint {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = controller.isHandleDragging
            ? controller.handleScale
            : CGSize(width: 1, height: 1)
        let rotation = controller.isHandleDragging ? controller.handleRotation : 0

        let topPoint = transformed(
            SelectionHandle.top.anchorPoint(in: bounds),
            around: center,
            scale: scale,
            rotation: rotation
        )
        if handle == .rotation {
            return CGPoint(
                x: topPoint.x + CGFloat(sin(rotation)) * 28,
                y: topPoint.y - CGFloat(cos(rotation)) * 28
            )
        }
        return transformed(
            handle.anchorPoint(in: bounds),
            around: center,
            scale: scale,
            rotation: rotation
        )
    }

    private func transformed(
        _ point: CGPoint,
        around center: CGPoint,
        scale: CGSize,
        rotation: Double
    ) -> CGPoint {
        let scaledX = (point.x - center.x) * scale.width
        let scaledY = (point.y - center.y) * scale.height
        let cosine = CGFloat(cos(rotation))
        let sine = CGFloat(sin(rotation))
        return CGPoint(
            x: center.x + scaledX * cosine - scaledY * sine,
            y: center.y + scaledX * sine + scaledY * cosine
        )
    }

    private enum SelectionHandle: CaseIterable, Hashable, Identifiable {
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

        func anchorPoint(in bounds: CGRect) -> CGPoint {
            switch self {
            case .topLeft:
                CGPoint(x: bounds.minX, y: bounds.minY)
            case .top, .rotation:
                CGPoint(x: bounds.midX, y: bounds.minY)
            case .topRight:
                CGPoint(x: bounds.maxX, y: bounds.minY)
            case .left:
                CGPoint(x: bounds.minX, y: bounds.midY)
            case .right:
                CGPoint(x: bounds.maxX, y: bounds.midY)
            case .bottomLeft:
                CGPoint(x: bounds.minX, y: bounds.maxY)
            case .bottom:
                CGPoint(x: bounds.midX, y: bounds.maxY)
            case .bottomRight:
                CGPoint(x: bounds.maxX, y: bounds.maxY)
            }
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
}
