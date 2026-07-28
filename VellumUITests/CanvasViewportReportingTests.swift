import Foundation
import PencilKit
import SwiftUI
import UIKit
@testable import Vellum
import VellumCore
import XCTest

/// Records the exact callback order so tests can distinguish synchronous viewport
/// delivery from a report that arrives only after the main run loop advances.
@MainActor
private final class ViewportRecorder {
    private(set) var reports: [CanvasViewport] = []

    func record(_ viewport: CanvasViewport) {
        reports.append(viewport)
    }
}

/// Hosts the production representable with only the callbacks needed to observe
/// its real PagedCanvasView and Coordinator viewport-reporting path.
@MainActor
private struct ViewportReportHarness: View {
    let canvasReference: NoteCanvasReference
    let recorder: ViewportRecorder

    var body: some View {
        PencilCanvasView(
            drawingData: nil,
            onDrawingChanged: { _ in },
            showsSystemToolPicker: false,
            onCanvasReady: { canvasView in
                canvasReference.canvasView = canvasView
            },
            onViewportChanged: { viewport in
                recorder.record(viewport)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Keeps the full UIKit/SwiftUI host graph alive so layout and scroll delegate
/// callbacks have the same window-backed behavior as the app.
@MainActor
private struct HostedViewportReportHarness {
    let recorder: ViewportRecorder
    let canvasReference: NoteCanvasReference
    let canvasView: PagedCanvasView
    let hostingController: UIHostingController<ViewportReportHarness>
    let window: UIWindow
}

@MainActor
final class CanvasViewportReportingTests: XCTestCase {
    /// A bounds-driven fit change must report within layoutIfNeeded itself so
    /// overlays cannot render one frame behind the newly resized canvas.
    func testLayoutDrivenBoundsChangeReportsViewportSynchronously() throws {
        let host = try makeHostedHarness(size: CGSize(width: 900, height: 1_200))
        defer { host.window.isHidden = true }

        let countBeforeResize = host.recorder.reports.count
        host.window.frame = CGRect(
            origin: .zero,
            size: CGSize(width: 700, height: 1_200)
        )
        host.window.layoutIfNeeded()

        XCTAssertEqual(
            host.canvasView.bounds.width,
            700,
            accuracy: 0.01,
            "window resize did not synchronously propagate to the live canvas bounds"
        )
        XCTAssertGreaterThan(
            host.recorder.reports.count,
            countBeforeResize,
            "layoutIfNeeded did not synchronously deliver a viewport report for the resized canvas"
        )
        let newestReport = try XCTUnwrap(
            host.recorder.reports.last,
            "resized canvas had no viewport report"
        )
        XCTAssertEqual(
            newestReport.zoomScale,
            PageLayout.minZoom(forViewportWidth: 700),
            accuracy: 0.01,
            "synchronous resize report did not contain the new fit zoom"
        )
    }

    /// A deferred report queued during a representable update must never arrive
    /// later and overwrite a newer viewport that was already reported synchronously.
    func testDeferredReportNeverRegressesPastSynchronousOne() throws {
        let host = try makeHostedHarness(size: CGSize(width: 900, height: 1_200))
        defer { host.window.isHidden = true }

        let offsets = try makeScrollableOffsets(in: host.canvasView)
        host.canvasView.performRepresentableUpdate {
            XCTAssertTrue(
                host.canvasView.isInRepresentableUpdate,
                "representable-update guard was not active while scheduling the stale report"
            )
            host.canvasView.contentOffset = offsets.stale
        }
        let staleOffset = host.canvasView.contentOffset
        XCTAssertFalse(
            host.canvasView.isInRepresentableUpdate,
            "representable-update guard remained active after its closure returned"
        )
        assertContentOffset(
            host.canvasView.contentOffset,
            equals: staleOffset,
            message: "stale test offset was clamped before its deferred report was queued"
        )

        host.canvasView.contentOffset = offsets.newer
        let newerOffset = host.canvasView.contentOffset
        XCTAssertGreaterThan(
            abs(newerOffset.y - staleOffset.y),
            1,
            "pixel-aligned stale and newer offsets were not meaningfully distinct"
        )
        assertContentOffset(
            host.canvasView.contentOffset,
            equals: newerOffset,
            message: "newer test offset was clamped before its synchronous report"
        )
        let immediateReport = try XCTUnwrap(
            host.recorder.reports.last,
            "newer offset did not synchronously produce a viewport report"
        )
        assertContentOffset(
            immediateReport.contentOffset,
            equals: newerOffset,
            message: "newer viewport waited behind the pending deferred report"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let finalReport = try XCTUnwrap(
            host.recorder.reports.last,
            "no viewport report remained after the deferred task fired"
        )
        assertContentOffset(
            finalReport.contentOffset,
            equals: newerOffset,
            message: "deferred viewport report regressed to the stale offset"
        )
    }

    /// Scroll callbacks raised inside updateUIView must be deferred to avoid a
    /// synchronous SwiftUI state mutation, then delivered on the next run-loop turn.
    func testReportsAreDeferredDuringRepresentableUpdate() throws {
        let host = try makeHostedHarness(size: CGSize(width: 900, height: 1_200))
        defer { host.window.isHidden = true }

        let someNewOffset = try makeScrollableOffsets(in: host.canvasView).stale
        let settledOffset = host.canvasView.contentOffset
        XCTAssertGreaterThan(
            abs(someNewOffset.y - settledOffset.y),
            0.01,
            "representable-update test offset matched the harness's settled offset"
        )
        let countBefore = host.recorder.reports.count
        host.canvasView.performRepresentableUpdate {
            XCTAssertTrue(
                host.canvasView.isInRepresentableUpdate,
                "representable-update guard was not active during the offset mutation"
            )
            host.canvasView.contentOffset = someNewOffset
        }
        let someNewOffsetActual = host.canvasView.contentOffset
        XCTAssertFalse(
            host.canvasView.isInRepresentableUpdate,
            "representable-update guard remained active after its closure returned"
        )
        assertContentOffset(
            host.canvasView.contentOffset,
            equals: someNewOffsetActual,
            message: "representable-update test offset was clamped"
        )
        XCTAssertEqual(
            host.recorder.reports.count,
            countBefore,
            "viewport callback fired synchronously during a representable update"
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertGreaterThan(
            host.recorder.reports.count,
            countBefore,
            "deferred viewport callback did not arrive after the run loop advanced"
        )
        let newestReport = try XCTUnwrap(
            host.recorder.reports.last,
            "deferred viewport callback produced no report"
        )
        assertContentOffset(
            newestReport.contentOffset,
            equals: someNewOffsetActual,
            message: "deferred viewport callback reported the wrong offset"
        )
    }

    private func makeHostedHarness(size: CGSize) throws -> HostedViewportReportHarness {
        let recorder = ViewportRecorder()
        let canvasReference = NoteCanvasReference()
        let harness = ViewportReportHarness(
            canvasReference: canvasReference,
            recorder: recorder
        )
        let hostingController = UIHostingController(rootView: harness)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))

        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        for _ in 0..<6 {
            hostingController.view.setNeedsLayout()
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.layoutIfNeeded()
            if let canvasView = canvasReference.canvasView,
               !canvasView.bounds.isEmpty {
                break
            }
        }

        let canvasView = try XCTUnwrap(
            canvasReference.canvasView,
            "PencilCanvasView.onCanvasReady did not provide a live PKCanvasView."
        )
        let laidOutCanvasView = try XCTUnwrap(
            canvasView.bounds.isEmpty ? nil : canvasView,
            "Live PKCanvasView had empty bounds after UIWindow layout and run-loop pumping: \(canvasView.bounds)."
        )
        let pagedCanvasView = try XCTUnwrap(
            laidOutCanvasView as? PagedCanvasView,
            "Live PKCanvasView was not the production PagedCanvasView subclass."
        )
        _ = try XCTUnwrap(
            pagedCanvasView.delegate as? PencilCanvasView.Coordinator,
            "Live PagedCanvasView delegate was not a PencilCanvasView.Coordinator."
        )
        let initialReport = try XCTUnwrap(
            recorder.reports.last,
            "Hosted canvas did not deliver its initial deferred fit-viewport report."
        )
        XCTAssertEqual(
            initialReport.zoomScale,
            PageLayout.minZoom(forViewportWidth: pagedCanvasView.bounds.width),
            accuracy: 0.01,
            "Hosted canvas's initial viewport report was not at fit zoom."
        )

        return HostedViewportReportHarness(
            recorder: recorder,
            canvasReference: canvasReference,
            canvasView: pagedCanvasView,
            hostingController: hostingController,
            window: window
        )
    }

    /// Derives two interior offsets from the live scroll geometry so delegate
    /// tests cannot pass or fail because UIScrollView silently clamps a guess.
    private func makeScrollableOffsets(
        in canvasView: PagedCanvasView
    ) throws -> (stale: CGPoint, newer: CGPoint) {
        let minimumY = -canvasView.contentInset.top
        let maximumY = max(
            minimumY,
            canvasView.contentSize.height - canvasView.bounds.height
                + canvasView.contentInset.bottom
        )
        let scrollableDistance = maximumY - minimumY
        let usableDistance = try XCTUnwrap(
            scrollableDistance > 1 ? scrollableDistance : nil,
            "Live canvas had no usable vertical scroll range: contentSize \(canvasView.contentSize), bounds \(canvasView.bounds), contentInset \(canvasView.contentInset)."
        )
        let restingX = -canvasView.contentInset.left

        return (
            stale: CGPoint(
                x: restingX,
                y: minimumY + usableDistance * 0.25
            ),
            newer: CGPoint(
                x: restingX,
                y: minimumY + usableDistance * 0.75
            )
        )
    }

    private func assertContentOffset(
        _ actual: CGPoint,
        equals expected: CGPoint,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.x,
            expected.x,
            accuracy: 0.01,
            "\(message): x was \(actual.x), expected \(expected.x).",
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.y,
            expected.y,
            accuracy: 0.01,
            "\(message): y was \(actual.y), expected \(expected.y).",
            file: file,
            line: line
        )
    }
}
