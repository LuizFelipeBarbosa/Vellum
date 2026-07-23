import Foundation
import PencilKit
import SwiftUI
import UIKit
@testable import Vellum
import VellumCore
import XCTest

@MainActor
private struct PaginationHarness: View {
    @State private var pageState: NotePageState
    @State private var canvasViewport = CanvasViewport(contentOffset: .zero, zoomScale: 1)
    let canvasReference: NoteCanvasReference
    let minimumFilledPages: Int

    init(
        pageState: NotePageState,
        canvasReference: NoteCanvasReference,
        minimumFilledPages: Int
    ) {
        _pageState = State(initialValue: pageState)
        self.canvasReference = canvasReference
        self.minimumFilledPages = minimumFilledPages
    }

    var body: some View {
        PencilCanvasView(
            drawingData: nil,
            onDrawingChanged: { _ in
                pageState.updateContent(
                    drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                    elements: [],
                    minimumFilledPages: minimumFilledPages
                )
            },
            isTransparent: true,
            tool: nil,
            showsSystemToolPicker: false,
            onCanvasReady: { canvasView in
                canvasReference.canvasView = canvasView
            },
            isDrawingEnabled: true,
            contentHeight: pageState.contentHeight,
            onViewportChanged: { viewport in
                canvasViewport = viewport
                pageState.updateViewport(
                    viewport,
                    viewportSize: canvasReference.canvasView?.bounds.size ?? .zero
                )
            },
            onExternalDrawingChange: {
                pageState.updateContent(
                    drawingBounds: canvasReference.canvasView?.drawing.bounds ?? .null,
                    elements: [],
                    minimumFilledPages: minimumFilledPages
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct HostedPaginationHarness {
    let pageState: NotePageState
    let canvasReference: NoteCanvasReference
    let canvasView: PKCanvasView
    let hostingController: UIHostingController<PaginationHarness>
    let window: UIWindow
}

@MainActor
final class PaginationLiveChainTests: XCTestCase {
    func testFreshHarnessShowsTwoPages() throws {
        let host = try makeHostedHarness()
        defer { host.window.isHidden = true }

        let actualPageCount = host.pageState.pageCount
        let expectedContentHeight =
            2 * PageGeometry.a4.pageHeight * host.canvasView.zoomScale
        let actualContentHeight = host.canvasView.contentSize.height

        XCTAssertEqual(
            actualPageCount,
            2,
            "Fresh live harness reported pageCount \(actualPageCount); expected 2."
        )
        XCTAssertEqual(
            actualContentHeight,
            expectedContentHeight,
            accuracy: 1.0,
            "Fresh live canvas contentSize.height was \(actualContentHeight); expected \(expectedContentHeight) for 2 pages at zoomScale \(host.canvasView.zoomScale)."
        )
    }

    func testMaterializedPagesShowOneTrailingBlankWithoutInk() {
        let pageState = NotePageState()

        pageState.updateContent(
            drawingBounds: .null,
            elements: [],
            minimumFilledPages: 3
        )

        XCTAssertEqual(pageState.pageCount, 4)
    }

    func testInkInTrailingBlankBandGrowsBeyondMaterializedPages() throws {
        let materializedPageCount = 3
        let host = try makeHostedHarness(
            minimumFilledPages: materializedPageCount
        )
        defer { host.window.isHidden = true }

        XCTAssertEqual(host.pageState.pageCount, materializedPageCount + 1)
        let trailingBandY =
            CGFloat(materializedPageCount) * PageGeometry.a4.pageHeight + 80
        host.canvasReference.canvasView?.drawing = makeDrawing(
            locations: [
                CGPoint(x: 300, y: trailingBandY),
                CGPoint(x: 340, y: trailingBandY + 20),
            ]
        )
        pumpRunLoop(for: host)

        XCTAssertEqual(host.pageState.pageCount, materializedPageCount + 2)
    }

    func testScrollCallbackResyncsStompedContentSize() throws {
        let host = try makeHostedHarness()
        defer { host.window.isHidden = true }

        let coordinator = try XCTUnwrap(
            host.canvasView.delegate as? PencilCanvasView.Coordinator,
            "Live PKCanvasView delegate was not a PencilCanvasView.Coordinator."
        )
        host.canvasView.contentSize = CGSize(
            width: PageLayout.contentWidth,
            height: host.pageState.contentHeight
        )

        coordinator.scrollViewDidScroll(host.canvasView)

        let expectedContentWidth = PageLayout.contentWidth * host.canvasView.zoomScale
        let expectedContentHeight = host.pageState.contentHeight * host.canvasView.zoomScale
        let actualContentSize = host.canvasView.contentSize

        XCTAssertEqual(
            actualContentSize.width,
            expectedContentWidth,
            accuracy: 1.0,
            "Scroll callback left live canvas contentSize.width at \(actualContentSize.width); expected \(expectedContentWidth) at zoomScale \(host.canvasView.zoomScale) after healing an unscaled content-size stomp."
        )
        XCTAssertEqual(
            actualContentSize.height,
            expectedContentHeight,
            accuracy: 1.0,
            "Scroll callback left live canvas contentSize.height at \(actualContentSize.height); expected \(expectedContentHeight) at zoomScale \(host.canvasView.zoomScale) after healing an unscaled content-size stomp."
        )
    }

    func testScrollStormDoesNotGrowPagesAndKeepsRangeCorrect() throws {
        let host = try makeHostedHarness()
        defer { host.window.isHidden = true }

        let baselinePageCount = host.pageState.pageCount
        var previousOffsetY: CGFloat = host.canvasView.contentOffset.y

        for iteration in 0..<40 {
            let requestedY = previousOffsetY + 120
            let maxOffsetY = max(
                0,
                host.canvasView.contentSize.height - host.canvasView.bounds.height
                    + host.canvasView.adjustedContentInset.bottom
            )
            let clampedY = min(requestedY, maxOffsetY)

            host.canvasView.contentOffset = CGPoint(x: 0, y: clampedY)
            pumpRunLoop(for: host, turns: 2)

            let actualOffsetY = host.canvasView.contentOffset.y
            let expectedHeight = (host.canvasView as? PagedCanvasView)?.expectedContentSize.height
            let unwrappedExpectedHeight = try XCTUnwrap(
                expectedHeight,
                "Iteration \(iteration): canvasView was not a PagedCanvasView at contentOffset.y \(actualOffsetY); could not read its own expectedContentSize.",
                file: #filePath,
                line: #line
            )

            XCTAssertEqual(
                host.canvasView.contentSize.height,
                unwrappedExpectedHeight,
                accuracy: 1.0,
                "Iteration \(iteration): contentSize.height was \(host.canvasView.contentSize.height); expected \(expectedHeight ?? -1) (canvas's own expectedContentSize) at contentOffset.y \(actualOffsetY)."
            )
            XCTAssertGreaterThanOrEqual(
                actualOffsetY,
                previousOffsetY - 0.5,
                "Iteration \(iteration): contentOffset.y regressed from \(previousOffsetY) to \(actualOffsetY) — something other than the test moved it backward (a scroll-position fight)."
            )

            previousOffsetY = actualOffsetY
        }

        let finalPageCount = host.pageState.pageCount
        XCTAssertEqual(
            finalPageCount,
            baselinePageCount,
            "After scrolling to contentOffset.y \(previousOffsetY) with no ink drawn, pageState.pageCount changed from \(baselinePageCount) to \(finalPageCount) — scrolling alone must never grow pageCount under the content-only-growth rule."
        )

        let finalMaxOffsetY = max(
            0,
            host.canvasView.contentSize.height - host.canvasView.bounds.height
                + host.canvasView.adjustedContentInset.bottom
        )
        XCTAssertEqual(
            previousOffsetY,
            finalMaxOffsetY,
            accuracy: 1.0,
            "After the scroll storm, contentOffset.y settled at \(previousOffsetY); expected it to have clamped at the last page's end \(finalMaxOffsetY) (contentSize.height \(host.canvasView.contentSize.height), bounds.height \(host.canvasView.bounds.height), adjustedContentInset.bottom \(host.canvasView.adjustedContentInset.bottom)) — scrolling should bounce/clamp at the end of the last page, not extend indefinitely."
        )
    }

    func testPencilOnlyPanGestureAllowsSingleFingerScroll() throws {
        let host = try makeHostedHarness()
        defer { host.window.isHidden = true }

        host.canvasView.drawingPolicy = .pencilOnly
        pumpRunLoop(for: host, turns: 2)

        let panAllowedTypes = host.canvasView.panGestureRecognizer.allowedTouchTypes.map(\.intValue)
        let drawingAllowedTypes = host.canvasView.drawingGestureRecognizer.allowedTouchTypes
            .map(\.intValue)
        XCTContext.runActivity(named: "Pencil-only touch-type inspection") { activity in
            let description = """
            drawingPolicy = .pencilOnly
            panGestureRecognizer.isEnabled = \(host.canvasView.panGestureRecognizer.isEnabled)
            panGestureRecognizer.minimumNumberOfTouches = \(host.canvasView.panGestureRecognizer.minimumNumberOfTouches)
            panGestureRecognizer.allowedTouchTypes (raw UITouch.TouchType values; [] = unrestricted) = \(panAllowedTypes)
            drawingGestureRecognizer.allowedTouchTypes = \(drawingAllowedTypes)
            canvasView.isScrollEnabled = \(host.canvasView.isScrollEnabled)
            """
            let attachment = XCTAttachment(string: description)
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        XCTAssertTrue(
            host.canvasView.panGestureRecognizer.isEnabled,
            "panGestureRecognizer.isEnabled was false under .pencilOnly drawingPolicy; one-finger scroll requires it enabled."
        )
        XCTAssertLessThanOrEqual(
            host.canvasView.panGestureRecognizer.minimumNumberOfTouches,
            1,
            "panGestureRecognizer.minimumNumberOfTouches was \(host.canvasView.panGestureRecognizer.minimumNumberOfTouches); expected <= 1 for one-finger scroll under .pencilOnly."
        )
        XCTAssertTrue(
            host.canvasView.isScrollEnabled,
            "canvasView.isScrollEnabled was false under .pencilOnly drawingPolicy."
        )

        let directTouchTypeRawValue = UITouch.TouchType.direct.rawValue
        let panExcludesDirectTouches = !panAllowedTypes.isEmpty
            && !panAllowedTypes.contains(directTouchTypeRawValue)
        XCTAssertFalse(
            panExcludesDirectTouches,
            "panGestureRecognizer.allowedTouchTypes \(panAllowedTypes) excludes direct (finger) touches under .pencilOnly drawingPolicy — this would break one-finger scrolling on device. drawingGestureRecognizer.allowedTouchTypes was \(drawingAllowedTypes)."
        )
    }

    func testInkOnPageTwoGrowsToThreePages() throws {
        let host = try makeHostedHarness()
        defer { host.window.isHidden = true }

        let strokeDrawing = makeDrawing(
            locations: [
                CGPoint(x: 300, y: 1_490),
                CGPoint(x: 340, y: 1_510),
            ]
        )

        host.canvasReference.canvasView?.drawing = strokeDrawing
        pumpRunLoop(for: host)

        let actualPageCount = host.pageState.pageCount
        let actualDrawingBottom = host.canvasView.drawing.bounds.maxY
        let expectedContentHeight =
            3 * PageGeometry.a4.pageHeight * host.canvasView.zoomScale
        let actualContentHeight = host.canvasView.contentSize.height

        XCTAssertEqual(
            actualPageCount,
            3,
            "Live ink callback chain reported pageCount \(actualPageCount); expected 3 after a page-2 stroke with drawing.bounds.maxY \(actualDrawingBottom)."
        )
        XCTAssertEqual(
            actualContentHeight,
            expectedContentHeight,
            accuracy: 1.0,
            "Live canvas contentSize.height was \(actualContentHeight); expected \(expectedContentHeight) for 3 pages at zoomScale \(host.canvasView.zoomScale) after pageCount became \(actualPageCount)."
        )
    }

    func testInkAtPageTwoBottomViaViewportSpace() throws {
        let host = try makeHostedHarness()
        defer { host.window.isHidden = true }

        let zoomScale = host.canvasView.zoomScale
        let pageTwoRect = PageGeometry.a4.pageRect(index: 1)
        let targetContentY = pageTwoRect.maxY - 30
        let targetContentPoint = CGPoint(x: 300, y: targetContentY)
        let visibleMargin = host.canvasView.bounds.height / 2
        let requestedContentOffsetY = max(
            0,
            targetContentY * zoomScale - visibleMargin
        )
        let maximumContentOffsetY = max(
            0,
            host.canvasView.contentSize.height - host.canvasView.bounds.height
        )

        host.canvasView.contentOffset = CGPoint(
            x: 0,
            y: min(requestedContentOffsetY, maximumContentOffsetY)
        )
        pumpRunLoop(for: host, turns: 2)

        let viewport = CanvasViewport(
            contentOffset: host.canvasView.contentOffset,
            zoomScale: host.canvasView.zoomScale
        )
        let viewPoint = viewport.viewPoint(fromContent: targetContentPoint)
        let roundTrippedContentPoint = viewport.contentPoint(fromView: viewPoint)
        let visibleViewportBounds = CGRect(
            origin: .zero,
            size: host.canvasView.bounds.size
        )

        XCTAssertEqual(
            roundTrippedContentPoint.x,
            targetContentPoint.x,
            accuracy: 1.0,
            "Viewport round-trip produced content-space x \(roundTrippedContentPoint.x); expected \(targetContentPoint.x). viewPoint was \(viewPoint), contentOffset was \(viewport.contentOffset), zoomScale was \(viewport.zoomScale), and canvas bounds were \(host.canvasView.bounds)."
        )
        XCTAssertEqual(
            roundTrippedContentPoint.y,
            targetContentY,
            accuracy: 1.0,
            "Viewport round-trip produced content-space y \(roundTrippedContentPoint.y); expected \(targetContentY). viewPoint was \(viewPoint), contentOffset was \(viewport.contentOffset), zoomScale was \(viewport.zoomScale), and canvas bounds were \(host.canvasView.bounds)."
        )
        XCTAssertGreaterThan(
            roundTrippedContentPoint.y,
            pageTwoRect.minY,
            "Content-space target y \(roundTrippedContentPoint.y) did not fall inside page 2's vertical span \(pageTwoRect.minY)..<\(pageTwoRect.maxY). contentOffset was \(viewport.contentOffset), zoomScale was \(viewport.zoomScale), and viewPoint was \(viewPoint)."
        )
        XCTAssertLessThan(
            roundTrippedContentPoint.y,
            pageTwoRect.maxY,
            "Content-space target y \(roundTrippedContentPoint.y) did not fall inside page 2's vertical span \(pageTwoRect.minY)..<\(pageTwoRect.maxY). contentOffset was \(viewport.contentOffset), zoomScale was \(viewport.zoomScale), and viewPoint was \(viewPoint)."
        )
        XCTAssertTrue(
            visibleViewportBounds.contains(viewPoint),
            "Viewport-mapped point \(viewPoint) was not visible within \(visibleViewportBounds). Target content point was \(targetContentPoint), contentOffset was \(viewport.contentOffset), zoomScale was \(viewport.zoomScale), and canvas bounds were \(host.canvasView.bounds)."
        )

        let strokeDrawing = makeDrawing(
            locations: [
                CGPoint(
                    x: targetContentPoint.x - 10,
                    y: targetContentPoint.y - 10
                ),
                CGPoint(
                    x: targetContentPoint.x + 10,
                    y: targetContentPoint.y
                ),
            ]
        )

        host.canvasReference.canvasView?.drawing = strokeDrawing
        pumpRunLoop(for: host)

        let actualDrawingBottom = host.canvasView.drawing.bounds.maxY
        let saneDrawingBottomRange = (targetContentY - 25)...(targetContentY + 25)
        let expectedPageCount = PageGeometry.a4.pageCount(forContentBottom: targetContentY)
        let actualPageCount = host.pageState.pageCount

        XCTAssertTrue(
            saneDrawingBottomRange.contains(actualDrawingBottom),
            "PKDrawing.bounds.maxY was \(actualDrawingBottom); expected it within \(saneDrawingBottomRange) around the targeted content-space y \(targetContentY), not in view/scaled space. contentOffset was \(viewport.contentOffset), zoomScale was \(viewport.zoomScale), and viewPoint was \(viewPoint)."
        )
        XCTAssertEqual(
            actualPageCount,
            expectedPageCount,
            "Viewport-mapped live ink reported pageCount \(actualPageCount); expected \(expectedPageCount) for targeted content-space y \(targetContentY) (actual drawing.bounds.maxY \(actualDrawingBottom), contentOffset \(viewport.contentOffset), zoomScale \(viewport.zoomScale), viewPoint \(viewPoint))."
        )
    }

    private func makeHostedHarness(
        minimumFilledPages: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> HostedPaginationHarness {
        let pageState = NotePageState()
        pageState.updateContent(
            drawingBounds: .null,
            elements: [],
            minimumFilledPages: minimumFilledPages
        )
        let canvasReference = NoteCanvasReference()
        let harness = PaginationHarness(
            pageState: pageState,
            canvasReference: canvasReference,
            minimumFilledPages: minimumFilledPages
        )
        let hostingController = UIHostingController(rootView: harness)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 1_032, height: 1_376)
        )

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
            "PencilCanvasView.onCanvasReady did not provide a live PKCanvasView.",
            file: file,
            line: line
        )
        let laidOutCanvasView = try XCTUnwrap(
            canvasView.bounds.isEmpty ? nil : canvasView,
            "Live PKCanvasView had empty bounds after UIWindow layout and run-loop pumping: \(canvasView.bounds).",
            file: file,
            line: line
        )

        return HostedPaginationHarness(
            pageState: pageState,
            canvasReference: canvasReference,
            canvasView: laidOutCanvasView,
            hostingController: hostingController,
            window: window
        )
    }

    private func pumpRunLoop(
        for host: HostedPaginationHarness,
        turns: Int = 4
    ) {
        for _ in 0..<turns {
            host.hostingController.view.setNeedsLayout()
            host.window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.window.layoutIfNeeded()
        }
    }

    private func makeDrawing(
        locations: [CGPoint],
        size: CGSize = CGSize(width: 4, height: 4)
    ) -> PKDrawing {
        let controlPoints = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: TimeInterval(index) * 0.1,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        )
        return PKDrawing(strokes: [stroke])
    }
}
