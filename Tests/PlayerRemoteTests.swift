import XCTest

final class PlayerRemoteTests: XCTestCase {
    func testOpenNavigateAndCloseSubtitles() {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotTab", "PlayerHUD"]
        app.launch()
        let subtitles = app.buttons["hud-subtitles"]
        let style = app.buttons["hud-subtitleStyle"]
        let remote = XCUIRemote.shared
        waitForFocus(subtitles)
        remote.press(.right)
        waitForFocus(style)
        remote.press(.left)
        waitForFocus(subtitles)
        remote.press(.select)
        waitForFocus(app.buttons["search-subtitles"])
        remote.press(.down)
        let off = app.buttons["Off"]
        waitForFocus(off)
        remote.press(.select)
        XCTAssertTrue(off.exists)
        remote.press(.menu)
        waitForFocus(subtitles)
    }

    private func waitForFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let focused = NSPredicate { _, _ in element.exists && element.hasFocus }
        let condition = XCTNSPredicateExpectation(predicate: focused, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 12), .completed, file: file, line: line)
    }
}
