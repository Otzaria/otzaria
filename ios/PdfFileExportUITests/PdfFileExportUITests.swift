import XCTest

/// Real Files/provider UI. No delegate callback or platform channel is faked.
final class PdfFileExportUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
    app = XCUIApplication(bundleIdentifier: "com.mendelg.otzaria")
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
  }

  override func tearDownWithError() throws {
    if let app = app {
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "PDF export final UI"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      app.terminate()
    }
    app = nil
    try super.tearDownWithError()
  }

  func testFilesSaveCopiesTheRealServiceFileAndReleasesStaging() {
    launch(caseName: "files-save")
    app.buttons["Export files-save fixture"].tap()
    waitForPicker()
    openTestDestination()
    let save = app.buttons["Save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertTrue(save.isEnabled)
    save.tap()
    waitForState("saved")
    XCTAssertEqual(evidence.label, "validated=true;stagingAbsent=true;status=saved")
  }

  func testFilesCancelTerminatesTheRealServiceWithoutCreatingADestination() {
    launch(caseName: "files-cancel")
    app.buttons["Export files-cancel fixture"].tap()
    waitForPicker()
    let cancel = app.buttons["Cancel"].firstMatch
    if cancel.exists && cancel.isHittable {
      cancel.tap()
    } else {
      let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
      XCTAssertTrue(navigation.exists && navigation.isHittable, app.debugDescription)
      navigation.swipeDown()
    }
    waitForState("cancelled")
    XCTAssertEqual(evidence.label, "validated=true;stagingAbsent=true;status=cancelled")
  }

  private var state: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "export-status").firstMatch
  }

  private var evidence: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "export-evidence").firstMatch
  }

  private func launch(caseName: String) {
    app.launch()
    XCTAssertTrue(state.waitForExistence(timeout: 60), app.debugDescription)
    waitForState("ready")
    XCTAssertTrue(app.buttons["Export \(caseName) fixture"].isEnabled)
  }

  private func waitForPicker() {
    let save = app.buttons["Save"].firstMatch
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND hittable == true"), object: save
    )
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, app.debugDescription)
    XCTAssertEqual(state.label, "pending", app.debugDescription)
  }

  private func waitForState(_ expected: String) {
    let predicate = NSPredicate(format: "label == %@", expected)
    let completion = XCTNSPredicateExpectation(predicate: predicate, object: state)
    XCTAssertEqual(XCTWaiter.wait(for: [completion], timeout: 60), .completed, app.debugDescription)
    XCTAssertTrue(evidence.exists)
  }

  private func tapLocation(_ label: String) {
    let cell = app.cells.containing(.staticText, identifier: label).firstMatch
    if cell.waitForExistence(timeout: 5) {
      cell.tap()
      return
    }
    let button = app.buttons[label].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing Files location \(label)\n\(app.debugDescription)")
    button.tap()
  }

  private func openTestDestination() {
    // A new owned Simulator has no iCloud account. Navigate the actual local
    // Files provider; missing locations fail, rather than becoming a mock/skip.
    if !app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch.exists {
      let browse = app.buttons["Browse"].firstMatch
      if browse.waitForExistence(timeout: 5) { browse.tap() }
    }
    tapLocation("On My iPhone")
    tapLocation("אוצריא")
    tapLocation("OtzariaExportUITest")
  }
}
