import XCTest

/// Launches notes in each supported orientation and watches for a stale zoom-reset
/// pill, which exposes viewport state that failed to settle at fit even without a
/// reliable mid-run simulator rotation.
@MainActor
final class RotationViewportSyncUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A portrait note must remain at fit throughout its initial settling window;
    /// checking every poll catches transient stale viewport reports that later clear.
    func testOpenNoteSettlesAtFitInPortrait() throws {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        _ = pageBadge(in: app)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            XCTAssertFalse(
                zoomResetPill(in: app).exists,
                "zoom reset pill appeared while the portrait note should remain settled at fit"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertFalse(
            zoomResetPill(in: app).exists,
            "zoom reset pill remained after the portrait note's settling window"
        )
    }

    /// Launching directly in landscape exercises the geometry path the simulator
    /// actually supports and proves both viewport fit and tracker rendering settle.
    func testOpenNoteSettlesAtFitInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        let app = XCUIApplication()
        app.launch()

        ShapeFlowTestHelpers.openSiteNotes(in: app)
        let badge = pageBadge(in: app)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            XCTAssertFalse(
                zoomResetPill(in: app).exists,
                "zoom reset pill appeared while the landscape note should remain settled at fit"
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertFalse(
            zoomResetPill(in: app).exists,
            "zoom reset pill remained after the landscape note's settling window"
        )
        XCTAssertTrue(badge.exists, "page tracker disappeared after landscape launch settled")
        XCTAssertFalse(
            badge.label.isEmpty,
            "page tracker label was empty after landscape launch settled"
        )
    }

    // MARK: - Helpers

    private func pageBadge(in app: XCUIApplication) -> XCUIElement {
        let badge = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+ / [0-9]+")
        ).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 15), "page tracker badge not found")
        return badge
    }

    private func zoomResetPill(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+%")
        ).firstMatch
    }
}
