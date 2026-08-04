//
//  GlucoMomentUITests.swift
//  GlucoMomentUITests
//
//  Created by zcy0602 on 2026/6/27.
//

import XCTest

final class GlucoMomentUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGlucoseRecordPersistsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["记录血糖"].firstMatch.tap()

        let valueField = app.textFields["血糖值，单位 mmol/L"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 3))
        valueField.tap()
        valueField.typeText("6.3")

        let saveButton = app.buttons["保存"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        let savedValue = app.staticTexts["6.3 mmol/L"]
        XCTAssertTrue(savedValue.waitForExistence(timeout: 3))

        app.terminate()
        app.launch()

        XCTAssertTrue(savedValue.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
