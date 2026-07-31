#if DEBUG
// PKCanvasView multi-finger undo and redo gestures cannot be synthesized by
// XCUITest. SplitSpikeUITests keeps this reduced two-pane harness permanently
// to regression-test per-pane undo isolation and focus-follows-touch without
// driving those gestures through the full app.
import Foundation
import PencilKit
import SwiftUI
import UIKit

@MainActor
struct SplitSpikeView: View {
    private static let minimumPaneWidth: CGFloat = 200
    private static let dividerWidth: CGFloat = 16

    @State private var undoManagerA = UndoManager()
    @State private var undoManagerB = UndoManager()
    @State private var strokesA = 0
    @State private var strokesB = 0
    @State private var lastTouch = "none"
    @State private var paneRatio: CGFloat = 0.5
    @State private var dragStartWidthA: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            controls

            GeometryReader { geometry in
                let paneWidth = max(
                    geometry.size.width - Self.dividerWidth,
                    Self.minimumPaneWidth * 2
                )
                let widthA = clampedPaneWidth(paneWidth * paneRatio, total: paneWidth)
                let widthB = paneWidth - widthA
                let accessibilityValue =
                    "strokesA:\(strokesA);strokesB:\(strokesB);"
                    + "canUndoA:\(undoManagerA.canUndo ? 1 : 0);"
                    + "canUndoB:\(undoManagerB.canUndo ? 1 : 0);"
                    + "lastTouch:\(lastTouch);"
                    + "widthA:\(Int(widthA.rounded()));widthB:\(Int(widthB.rounded()))"

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        SplitSpikeCanvas(
                            paneName: "A",
                            backgroundColor: UIColor(
                                red: 0.94,
                                green: 0.97,
                                blue: 1,
                                alpha: 1
                            ),
                            undoManager: undoManagerA,
                            onStrokeCountChanged: { strokesA = $0 },
                            onTouchDown: { lastTouch = "A" }
                        )
                        .frame(width: widthA)
                        .clipped()

                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .overlay {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.7))
                                    .frame(width: 4, height: 64)
                            }
                            .frame(width: Self.dividerWidth)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let startWidth = dragStartWidthA ?? widthA
                                        if dragStartWidthA == nil {
                                            dragStartWidthA = startWidth
                                        }
                                        let proposedWidth = startWidth + value.translation.width
                                        paneRatio = clampedPaneWidth(
                                            proposedWidth,
                                            total: paneWidth
                                        ) / paneWidth
                                    }
                                    .onEnded { _ in
                                        dragStartWidthA = nil
                                    }
                            )

                        SplitSpikeCanvas(
                            paneName: "B",
                            backgroundColor: UIColor(
                                red: 0.94,
                                green: 1,
                                blue: 0.95,
                                alpha: 1
                            ),
                            undoManager: undoManagerB,
                            onStrokeCountChanged: { strokesB = $0 },
                            onTouchDown: { lastTouch = "B" }
                        )
                        .frame(width: widthB)
                        .clipped()
                    }
                    .frame(
                        width: paneWidth + Self.dividerWidth,
                        height: geometry.size.height,
                        alignment: .leading
                    )

                    Color.clear
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("vellum-split-spike-state")
                        .accessibilityValue(accessibilityValue)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Text("Split Spike")
                .font(.headline)

            Text("A: \(strokesA)  B: \(strokesB)  Last touch: \(lastTouch)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button("Undo A") {
                undoManagerA.undo()
            }
            .disabled(!undoManagerA.canUndo)

            Button("Undo B") {
                undoManagerB.undo()
            }
            .disabled(!undoManagerB.canUndo)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func clampedPaneWidth(_ proposedWidth: CGFloat, total: CGFloat) -> CGFloat {
        min(
            max(proposedWidth, Self.minimumPaneWidth),
            total - Self.minimumPaneWidth
        )
    }
}

@MainActor
private struct SplitSpikeCanvas: UIViewRepresentable {
    let paneName: String
    let backgroundColor: UIColor
    let undoManager: UndoManager
    let onStrokeCountChanged: @MainActor (Int) -> Void
    let onTouchDown: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            paneName: paneName,
            onStrokeCountChanged: onStrokeCountChanged,
            onTouchDown: onTouchDown
        )
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = backgroundColor

        let canvasView = PagedCanvasView()
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.paneUndoManager = undoManager
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvasView.backgroundColor = backgroundColor
        canvasView.isOpaque = true
        canvasView.contentInsetAdjustmentBehavior = .never

        containerView.addSubview(canvasView)
        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: containerView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        let touchDownObserver = TouchDownObserverGestureRecognizer {
            [weak coordinator = context.coordinator] in
            coordinator?.handleTouchDown()
        }
        containerView.addGestureRecognizer(touchDownObserver)

        context.coordinator.canvasView = canvasView
        return containerView
    }

    func updateUIView(_ containerView: UIView, context: Context) {
        containerView.backgroundColor = backgroundColor
        context.coordinator.onStrokeCountChanged = onStrokeCountChanged
        context.coordinator.onTouchDown = onTouchDown
        context.coordinator.canvasView?.paneUndoManager = undoManager
        context.coordinator.canvasView?.backgroundColor = backgroundColor
    }

    static func dismantleUIView(_ containerView: UIView, coordinator: Coordinator) {
        coordinator.canvasView?.delegate = nil
        coordinator.canvasView?.paneUndoManager = nil
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let paneName: String
        var onStrokeCountChanged: @MainActor (Int) -> Void
        var onTouchDown: @MainActor () -> Void
        weak var canvasView: PagedCanvasView?

        init(
            paneName: String,
            onStrokeCountChanged: @escaping @MainActor (Int) -> Void,
            onTouchDown: @escaping @MainActor () -> Void
        ) {
            self.paneName = paneName
            self.onStrokeCountChanged = onStrokeCountChanged
            self.onTouchDown = onTouchDown
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onStrokeCountChanged(canvasView.drawing.strokes.count)
        }

        func handleTouchDown() {
            NSLog("SplitSpike focus %@", paneName)
            onTouchDown()
        }
    }
}

#endif
