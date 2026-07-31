import SwiftUI
import UIKit

@MainActor
struct EdgeSwipeDetector: UIViewRepresentable {
    let isEnabled: Bool
    let onSwipeRight: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            onSwipeRight: onSwipeRight
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = EdgeSwipeDetectorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.syncInstallation(for: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.syncInstallation(for: view)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let view = uiView as? EdgeSwipeDetectorView {
            view.coordinator = nil
        }
        coordinator.dismantleInstallation()
    }

    @MainActor
    final class Coordinator: NSObject {
        var isEnabled: Bool
        var onSwipeRight: @MainActor () -> Void
        weak var stripView: UIView?
        weak var installedView: UIView?

        private lazy var edgeSwipeObserver = EdgeSwipeObserverGestureRecognizer(
            shouldReceiveTouch: { [weak self] touch in
                self?.shouldReceive(touch) ?? false
            },
            onSwipeRight: { [weak self] in
                self?.onSwipeRight()
            }
        )

        init(
            isEnabled: Bool,
            onSwipeRight: @escaping @MainActor () -> Void
        ) {
            self.isEnabled = isEnabled
            self.onSwipeRight = onSwipeRight
            super.init()
        }

        func syncInstallation(for stripView: UIView) {
            self.stripView = stripView

            guard let targetView = stripView.window else {
                if let installedView {
                    installedView.removeGestureRecognizer(edgeSwipeObserver)
                }
                installedView = nil
                return
            }
            guard targetView !== installedView else { return }

            if let installedView {
                installedView.removeGestureRecognizer(edgeSwipeObserver)
            }
            targetView.addGestureRecognizer(edgeSwipeObserver)
            installedView = targetView
        }

        func dismantleInstallation() {
            if let installedView {
                installedView.removeGestureRecognizer(edgeSwipeObserver)
            }
            stripView = nil
            installedView = nil
        }

        private func shouldReceive(_ touch: UITouch) -> Bool {
            guard isEnabled,
                  let stripView,
                  let window = stripView.window else {
                return false
            }
            let windowLocation = touch.location(in: window)
            let stripLocation = stripView.convert(windowLocation, from: window)
            return stripView.bounds.contains(stripLocation)
        }
    }
}

@MainActor
private final class EdgeSwipeDetectorView: UIView {
    weak var coordinator: EdgeSwipeDetector.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        coordinator?.syncInstallation(for: self)
    }
}

@MainActor
final class EdgeSwipeObserverGestureRecognizer:
    UIGestureRecognizer,
    UIGestureRecognizerDelegate {
    private let shouldReceiveTouch: @MainActor (UITouch) -> Bool
    private let onSwipeRight: @MainActor () -> Void
    private var initialTouchPoint: CGPoint?
    private var didSwipeRight = false

    init(
        shouldReceiveTouch: @escaping @MainActor (UITouch) -> Bool,
        onSwipeRight: @escaping @MainActor () -> Void
    ) {
        self.shouldReceiveTouch = shouldReceiveTouch
        self.onSwipeRight = onSwipeRight
        super.init(target: nil, action: nil)
        allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
        ]
        cancelsTouchesInView = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        initialTouchPoint = touches.first?.location(in: view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !didSwipeRight,
              let initialTouchPoint,
              let currentTouchPoint = touches.first?.location(in: view) else {
            return
        }
        let dx = currentTouchPoint.x - initialTouchPoint.x
        let dy = currentTouchPoint.y - initialTouchPoint.y
        guard dx > 30, dx > abs(dy) else { return }

        didSwipeRight = true
        onSwipeRight()
        state = .failed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent
    ) {
        state = .failed
    }

    override func reset() {
        super.reset()
        initialTouchPoint = nil
        didSwipeRight = false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        shouldReceiveTouch(touch)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer:
            UIGestureRecognizer
    ) -> Bool {
        true
    }
}
