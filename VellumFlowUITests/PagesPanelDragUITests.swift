import XCTest

/// Drives the pages panel with real touch events to cover the gesture
/// arbitration that unit tests cannot: hold-and-drag reorder from the
/// thumbnail center, tap-to-select, and delete-badge protection.
final class PagesPanelDragUITests: XCTestCase {

    /// Three real pages plus the trailing blank page the panel always appends.
    /// The seeded note already ships three, so a healthy run adds nothing.
    private static let requiredPageTotal = 4

    /// Bounds both halves of the fixture: enough to reach
    /// `requiredPageTotal` from a one-page note, and few enough that a badge
    /// which never updates fails fast instead of adding pages forever.
    private static let maximumPageChange = 4

    /// Pages this test added to reach `requiredPageTotal`, removed again in
    /// teardown. Held on the case rather than in a teardown block so cleanup
    /// still runs after the failure that stops the test method.
    private var addedPages = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
        addedPages = 0
    }

    override func tearDownWithError() throws {
        guard addedPages > 0 else { return }
        let added = addedPages
        addedPages = 0
        deleteTrailingPages(added, in: XCUIApplication())
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

        // Pin the note to three real pages instead of adding one
        // unconditionally: nothing here ever removed the extra page, so every
        // run used to leave the note bigger than it found it.
        addedPages = prepareFixture(in: app, badge: badge)
        let total = pageTotal(of: badge)
        XCTAssertEqual(
            total, Self.requiredPageTotal,
            "fixture did not settle on three real pages plus the blank page"
        )

        let row1 = pageRow(1, in: app)
        let row2 = pageRow(2, in: app)
        XCTAssertTrue(row1.waitForExistence(timeout: 5), "page row 1 not found")
        XCTAssertTrue(row2.waitForExistence(timeout: 5), "page row 2 not found")

        // A reorder can only preserve thumbnails that are already cached, so
        // the assertion below only means something once the panel's first
        // render pass has finished. Rows are placeholders until then — the
        // trailing blank page in particular renders last — and dragging early
        // would blame the reorder for a render that had simply not happened.
        waitForThumbnailsToRender(in: app)

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
            "thumbnails reloaded after reorder: rows \(placeholderRowLabels(in: app))"
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

        // Dismiss whichever presentation this is — on iPad the dialog is a
        // popover, which drops Cancel and closes on a tap outside — and then
        // confirm it is gone. Probing `exists` once and moving on could leave
        // a still-animating dialog up for the next test.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else {
            app.staticTexts["Pages"].tap()
        }
        XCTAssertTrue(
            waitUntil { !dialogTitle.exists },
            "delete dialog stayed up after being dismissed"
        )
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

    // MARK: - Page fixture

    /// Brings the note to exactly `requiredPageTotal` and returns how many
    /// pages it had to add, so teardown can put the note back.
    ///
    /// Exactness matters: at this size every row's thumbnail stays cached,
    /// which is what makes the post-reorder placeholder assertion meaningful.
    /// Rows further down the panel sit in the accessibility tree without ever
    /// rendering, so a note left oversized by an older run would report
    /// placeholders no amount of waiting can clear.
    private func prepareFixture(in app: XCUIApplication, badge: XCUIElement) -> Int {
        let addPage = app.buttons["Add page"]
        XCTAssertTrue(addPage.waitForExistence(timeout: 5), "add page button not found")

        var added = 0
        while pageTotal(of: badge) < Self.requiredPageTotal {
            guard added < Self.maximumPageChange else {
                XCTFail("page total stalled at \(pageTotal(of: badge)) after \(added) adds")
                return added
            }
            let expectedTotal = pageTotal(of: badge) + 1
            addPage.tap()
            added += 1
            XCTAssertTrue(
                waitUntil { self.pageTotal(of: badge) == expectedTotal },
                "page total did not reach \(expectedTotal) after Add page"
            )
        }

        // Anything above the target is a leftover from an interrupted run of
        // this suite, so trimming it repairs the container rather than
        // discarding work: only this suite ever adds pages to the fixture.
        let surplus = pageTotal(of: badge) - Self.requiredPageTotal
        guard surplus > 0 else { return added }
        XCTAssertLessThanOrEqual(
            surplus, Self.maximumPageChange,
            "fixture note has \(surplus) unexpected pages; not trimming that many"
        )
        deleteTrailingPages(surplus, in: app)

        // Deleting scrolls both the canvas and the panel to the surviving
        // page, which leaves row 1 out of reach. Relaunching puts the scenario
        // on the same footing a clean container would give it.
        app.terminate()
        app.launch()
        openSiteNotes(in: app)
        pageBadge(in: app).tap()
        XCTAssertTrue(
            app.staticTexts["Pages"].waitForExistence(timeout: 5),
            "pages panel did not reopen after trimming the fixture"
        )
        return added
    }

    /// Deletes `count` pages from the end of the note. Also runs from
    /// teardown, so it reopens the panel itself and reports what it could not
    /// clean up rather than silently leaving the note bigger than it found it.
    private func deleteTrailingPages(_ count: Int, in app: XCUIApplication) {
        let badge = pageBadge(in: app)
        for _ in 0..<count {
            let panelTitle = app.staticTexts["Pages"]
            if !panelTitle.exists {
                badge.tap()
                XCTAssertTrue(
                    panelTitle.waitForExistence(timeout: 5),
                    "pages panel did not reopen for cleanup"
                )
            }

            // The last row is the always-present blank page and carries no
            // delete badge, so the last real page is one above the total.
            let totalBefore = pageTotal(of: badge)
            let trash = app.buttons["Delete page \(totalBefore - 1)"]
            XCTAssertTrue(trash.waitForExistence(timeout: 5), "cleanup found no delete badge")
            trash.tap()

            let confirm = app.buttons["Delete"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5), "cleanup found no Delete button")
            confirm.tap()

            XCTAssertTrue(
                waitUntil { self.pageTotal(of: badge) == totalBefore - 1 },
                "cleanup did not shrink the note to \(totalBefore - 1)"
            )
        }

        // Autosave is debounced, and the next test relaunches the app: without
        // this pause the last deletion never reaches disk and the page comes
        // back, which is exactly the growth this cleanup exists to prevent.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }

    // MARK: - Helpers

    private func loadingPlaceholders(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "value == 'Loading'"))
    }

    /// Blocks until every materialized row has swapped its placeholder for a
    /// rendered thumbnail, which is the same measurement the post-reorder
    /// assertion makes — so the reorder is judged against a warm cache only.
    private func waitForThumbnailsToRender(in app: XCUIApplication) {
        XCTAssertTrue(
            waitUntil(timeout: 20) { self.loadingPlaceholders(in: app).count == 0 },
            "thumbnails never finished rendering: rows \(placeholderRowLabels(in: app))"
        )
    }

    private func placeholderRowLabels(in app: XCUIApplication) -> [String] {
        loadingPlaceholders(in: app).allElementsBoundByIndex.map { $0.label }
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

    /// Polls rather than building an XCTest expectation so the same helper
    /// works from teardown, where the case no longer waits on expectations.
    /// Each probe is an accessibility query, so the loop is never tight.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }
}
