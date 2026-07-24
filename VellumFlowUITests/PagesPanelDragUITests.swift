import XCTest

/// Drives the pages panel with real touch events to cover the gesture
/// arbitration that unit tests cannot: hold-and-drag reorder from the
/// thumbnail center, tap-to-select, and delete-badge protection.
final class PagesPanelDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHoldAndDragFromThumbnailCenterReordersPages() throws {
        try runReorderScenario(orientation: .portrait)
    }

    func testHoldAndDragReordersPagesInLandscape() throws {
        try runReorderScenario(orientation: .landscapeLeft)
    }

    private func runReorderScenario(orientation: UIDeviceOrientation) throws {
        XCUIDevice.shared.orientation = orientation
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        let app = XCUIApplication()
        app.launch()

        openSiteNotes(in: app)
        let badge = pageBadge(in: app)
        badge.tap()

        let panelTitle = app.staticTexts["Pages"]
        XCTAssertTrue(panelTitle.waitForExistence(timeout: 5), "pages panel did not open")

        // Guarantee at least three real (materialized) pages.
        let addPage = app.buttons["Add page"]
        XCTAssertTrue(addPage.waitForExistence(timeout: 5), "add page button not found")
        addPage.tap()
        while pageTotal(of: badge) < 3 {
            addPage.tap()
        }
        let total = pageTotal(of: badge)

        let row1 = pageRow(1, in: app)
        let row2 = pageRow(2, in: app)
        XCTAssertTrue(row1.waitForExistence(timeout: 5), "page row 1 not found")
        XCTAssertTrue(row2.exists, "page row 2 not found")

        // The original bug: a press starting on the thumbnail itself never
        // lifted the row. After a real reorder the canvas scrolls to the
        // moved page, so the tracker badge must read "2 / total".
        row1.press(forDuration: 0.7, thenDragTo: row2)

        let moved = expectation(
            for: NSPredicate(format: "label == %@", "2 / \(total)"),
            evaluatedWith: badge
        )
        wait(for: [moved], timeout: 5)

        // Reordering must remap cached thumbnails, not blank them: no row
        // may fall back to its loading placeholder after the drop.
        XCTAssertEqual(
            loadingPlaceholders(in: app).count, 0,
            "thumbnails reloaded after reorder"
        )

        // Quick tap still selects: panel closes and canvas shows that page.
        pageRow(1, in: app).tap()
        let closed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: panelTitle
        )
        wait(for: [closed], timeout: 5)
        XCTAssertEqual(badge.label, "1 / \(total)")
    }

    func testHoldOnDeleteBadgeShowsDialogInsteadOfLifting() throws {
        let app = XCUIApplication()
        app.launch()

        openSiteNotes(in: app)
        let badge = pageBadge(in: app)
        let totalBefore = pageTotal(of: badge)
        badge.tap()
        XCTAssertTrue(app.staticTexts["Pages"].waitForExistence(timeout: 5))

        let trash = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "Delete page [0-9]+")
        ).firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 5), "delete badge not found")

        // A hold on the badge must not lift the row; the button still fires
        // on release, so the confirmation dialog appears and no move happens.
        trash.press(forDuration: 0.7)

        let dialogTitle = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "Delete page [0-9]+\\?")
        ).firstMatch
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: 5), "delete dialog did not appear")
        XCTAssertEqual(pageTotal(of: badge), totalBefore, "page count changed unexpectedly")

        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            app.staticTexts["Pages"].tap()
        }
    }

    /// Guards the reorder test's no-placeholder assertion against going
    /// vacuous: on a cold cache the placeholders must be queryable at all.
    /// The slow-render argument holds placeholders on screen long enough to
    /// outlast XCUITest's tap/quiescence latency.
    func testLoadingPlaceholdersAreQueryableOnColdOpen() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-thumbnail-slow-render")
        app.launch()
        openSiteNotes(in: app)
        pageBadge(in: app).tap()
        XCTAssertTrue(
            loadingPlaceholders(in: app).firstMatch.waitForExistence(timeout: 5),
            "loading placeholders not visible to the accessibility tree"
        )
    }

    // MARK: - Helpers

    private func loadingPlaceholders(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "value == 'Loading'"))
    }

    private func openSiteNotes(in app: XCUIApplication) {
        let card = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'Site notes'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Site notes card not found")
        card.tap()
    }

    private func pageBadge(in app: XCUIApplication) -> XCUIElement {
        let badge = app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "[0-9]+ / [0-9]+")
        ).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 15), "page tracker badge not found")
        return badge
    }

    private func pageRow(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label MATCHES %@", "^\(number)$")
        ).firstMatch
    }

    private func pageTotal(of badge: XCUIElement) -> Int {
        Int(badge.label.components(separatedBy: " / ").last ?? "") ?? 0
    }
}
