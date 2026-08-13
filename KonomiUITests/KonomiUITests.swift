import XCTest

final class KonomiUITests: XCTestCase {
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-KonomiUITestScenario", scenario]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Taste"].waitForExistence(timeout: 10))
        return app
    }

    private func selectTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()

        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: tab
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    func testNormalLaunchShowsTaste() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Taste"].waitForExistence(timeout: 10))
    }

    func testTasteContinueOpensMediaDetail() throws {
        let app = launch(scenario: "building")

        let item = app.buttons["UI Test In Progress"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        XCTAssertTrue(app.navigationBars["UI Test In Progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current Creator"].exists)
    }

    func testPersistenceFailureCanRetryIntoTaste() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-KonomiSimulatePersistenceFailureOnce")
        app.launch()

        XCTAssertTrue(app.staticTexts["Konomi Couldn't Open Your Library"].waitForExistence(timeout: 10))
        let retryButton = app.buttons["Try Again"]
        XCTAssertTrue(retryButton.exists)

        let details = app.buttons["Technical Details"]
        if details.exists {
            details.tap()
            XCTAssertTrue(app.staticTexts["Simulated persistence failure for UI testing."].exists)
        }

        retryButton.tap()
        XCTAssertTrue(app.tabBars.buttons["Taste"].waitForExistence(timeout: 10))
    }

    func testLibraryDeletionCanBeUndone() throws {
        let app = launch(scenario: "mature")
        selectTab("Library", in: app)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any)["library-row-UI Test Library Item"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let swipeStart = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let swipeEnd = row.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        swipeStart.press(forDuration: 0.1, thenDragTo: swipeEnd)
        app.buttons["Delete"].tap()

        let undo = app.buttons["Undo delete UI Test Library Item"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists)
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testRecommendationDismissalCanBeUndone() throws {
        let app = launch(scenario: "mature")
        selectTab("Discover", in: app)
        XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 5))

        let title = app.staticTexts["UI Test Second Recommendation"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["Dismiss"].firstMatch.tap()

        let undo = app.buttons["Undo dismissal of UI Test Second Recommendation"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists)
        undo.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    func testRecommendationTypeFiltersCurrentSnapshotWithoutNetwork() throws {
        let app = launch(scenario: "mature")
        selectTab("Discover", in: app)

        let bookTitle = app.staticTexts["UI Test Recommendation"]
        let movieTitle = app.staticTexts["UI Test Second Recommendation"]
        XCTAssertTrue(bookTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(movieTitle.exists)

        app.buttons["Books"].tap()
        XCTAssertTrue(bookTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(movieTitle.exists)

        app.buttons["Movies"].tap()
        XCTAssertTrue(movieTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(bookTitle.exists)

        app.buttons["TV Shows"].tap()
        XCTAssertTrue(app.staticTexts["No tv show picks in this set"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Generate TV Show Recommendations"].exists)

        app.buttons["All"].tap()
        XCTAssertTrue(bookTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(movieTitle.exists)
    }

    func testEmptyTastePrioritizesAUsableStart() throws {
        let app = launch(scenario: "empty")

        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertTrue(app.tabBars.buttons["Taste"].exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Discover"].exists)
        XCTAssertTrue(app.staticTexts["Teach Konomi what you love"].exists)
        let addButton = app.buttons["Add one title"]
        XCTAssertTrue(addButton.exists)
        if !addButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(addButton.isHittable)
        XCTAssertTrue(app.buttons["Connect TMDB for Quick Setup"].exists)
        XCTAssertFalse(app.staticTexts["Nothing in Progress"].exists)
        XCTAssertFalse(app.staticTexts["No Recommendations Yet"].exists)

        selectTab("Discover", in: app)
        let openLibrary = app.buttons["Open Library"]
        XCTAssertTrue(openLibrary.waitForExistence(timeout: 5))
        openLibrary.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    func testSettingsAndConnectionsRoute() throws {
        let app = launch(scenario: "empty")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Preferences"].exists)
        XCTAssertTrue(app.staticTexts["Library & Data"].exists)
        XCTAssertTrue(app.staticTexts["About"].exists)

        app.buttons["Connections"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Anthropic"].exists)
        XCTAssertTrue(app.staticTexts["Taste profiles and recommendations"].exists)
        XCTAssertTrue(app.staticTexts["TMDB"].exists)
        XCTAssertTrue(app.staticTexts["Movie and TV search, plus Quick Setup"].exists)
        XCTAssertTrue(app.staticTexts["Google Books"].exists)
        XCTAssertTrue(app.staticTexts["Optional import and cover fallback"].exists)

        app.navigationBars["Connections"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Taste"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3)
    }

    func testLibraryMenusAndInsightsRender() throws {
        let app = launch(scenario: "mature")

        selectTab("Library", in: app)
        app.buttons["Media filter"].tap()
        XCTAssertTrue(app.buttons["Books"].waitForExistence(timeout: 5))
        app.buttons["Books"].tap()

        app.buttons["Sort Library"].tap()
        XCTAssertTrue(app.buttons["Title"].waitForExistence(timeout: 5))
        app.buttons["Title"].tap()

        selectTab("Taste", in: app)
        let insightsButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Your year'")
        ).firstMatch
        XCTAssertTrue(insightsButton.waitForExistence(timeout: 5))
        insightsButton.tap()

        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your Score Distribution"].exists)
    }
}
