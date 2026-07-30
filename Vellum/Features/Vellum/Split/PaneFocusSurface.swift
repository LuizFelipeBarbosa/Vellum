import SwiftUI
import UIKit

@MainActor
struct PaneFocusSurface: UIViewRepresentable {
    let paneContext: PaneContext

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pane: paneContext.pane,
            onFocus: paneContext.onFocus
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.syncInstallation()
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.pane = paneContext.pane
        context.coordinator.onFocus = paneContext.onFocus
        context.coordinator.syncInstallation()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.dismantleInstallation()
    }

    @MainActor
    final class Coordinator: NSObject {
        var pane: NotePane
        var onFocus: () -> Void
        weak var installedView: UIView?

        private lazy var touchDownObserver = TouchDownObserverGestureRecognizer {
            [weak self] in
            self?.onFocus()
        }

        init(pane: NotePane, onFocus: @escaping () -> Void) {
            self.pane = pane
            self.onFocus = onFocus
            super.init()
        }

        func syncInstallation() {
            guard let targetView = pane.canvasReference.canvasView?.superview,
                  targetView !== installedView else { return }

            if let installedView {
                installedView.removeGestureRecognizer(touchDownObserver)
            }
            targetView.addGestureRecognizer(touchDownObserver)
            installedView = targetView
        }

        func dismantleInstallation() {
            if let installedView {
                installedView.removeGestureRecognizer(touchDownObserver)
            }
            installedView = nil
        }
    }
}

@MainActor
final class TouchDownObserverGestureRecognizer:
    UIGestureRecognizer,
    UIGestureRecognizerDelegate {
    private let onTouchDown: @MainActor () -> Void

    init(onTouchDown: @escaping @MainActor () -> Void) {
        self.onTouchDown = onTouchDown
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
        ]
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchDown()
        state = .failed
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
