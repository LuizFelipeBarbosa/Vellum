import Foundation
import PencilKit
import SwiftUI

@MainActor
struct PencilCanvasView: UIViewRepresentable {
    let drawingData: Data?
    let onDrawingChanged: (Data) -> Void
    var isTransparent: Bool = false
    var tool: (any PKTool)? = nil
    var showsSystemToolPicker: Bool = true
    var onCanvasReady: ((PKCanvasView) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = isTransparent ? .clear : .white
        canvasView.isOpaque = !isTransparent
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 3
        canvasView.bouncesZoom = true

        if let tool {
            canvasView.tool = tool
        }

        if showsSystemToolPicker {
            context.coordinator.toolPicker.addObserver(canvasView)
            context.coordinator.isObservingToolPicker = true
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        onCanvasReady?(canvasView)

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.onDrawingChanged = onDrawingChanged
        canvasView.backgroundColor = isTransparent ? .clear : .white
        canvasView.isOpaque = !isTransparent

        if let tool, !Self.toolsMatch(canvasView.tool, tool) {
            canvasView.tool = tool
        }

        let beganObservingToolPicker: Bool
        if showsSystemToolPicker {
            if !context.coordinator.isObservingToolPicker {
                context.coordinator.toolPicker.addObserver(canvasView)
                context.coordinator.isObservingToolPicker = true
                context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
                canvasView.becomeFirstResponder()
                beganObservingToolPicker = true
            } else {
                beganObservingToolPicker = false
            }
        } else if context.coordinator.isObservingToolPicker {
            context.coordinator.toolPicker.setVisible(false, forFirstResponder: canvasView)
            context.coordinator.toolPicker.removeObserver(canvasView)
            context.coordinator.isObservingToolPicker = false
            beganObservingToolPicker = false
        } else {
            beganObservingToolPicker = false
        }

        guard let drawingData,
              drawingData != canvasView.drawing.dataRepresentation(),
              let drawing = try? PKDrawing(data: drawingData) else {
            return
        }

        context.coordinator.isUpdatingFromModel = true
        canvasView.drawing = drawing
        context.coordinator.isUpdatingFromModel = false

        if showsSystemToolPicker,
           !beganObservingToolPicker,
           canvasView.window != nil,
           !canvasView.isFirstResponder {
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ canvasView: PKCanvasView, coordinator: Coordinator) {
        if coordinator.isObservingToolPicker {
            coordinator.toolPicker.removeObserver(canvasView)
        }
    }

    private static func toolsMatch(_ lhs: any PKTool, _ rhs: any PKTool) -> Bool {
        if let lhs = lhs as? PKInkingTool, let rhs = rhs as? PKInkingTool {
            return lhs == rhs
        }
        if let lhs = lhs as? PKEraserTool, let rhs = rhs as? PKEraserTool {
            return lhs == rhs
        }
        if let lhs = lhs as? PKLassoTool, let rhs = rhs as? PKLassoTool {
            return lhs == rhs
        }
        return false
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var onDrawingChanged: (Data) -> Void
        var isUpdatingFromModel = false
        var isObservingToolPicker = false

        init(onDrawingChanged: @escaping (Data) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromModel else { return }
            onDrawingChanged(canvasView.drawing.dataRepresentation())
        }
    }
}
