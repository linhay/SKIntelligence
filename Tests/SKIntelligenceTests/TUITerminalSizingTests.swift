import XCTest
@testable import SKICLI

final class TUITerminalSizingTests: XCTestCase {
    func testNormalizePrefersWinsizeWhenValid() {
        let size = TUITerminalSizing.normalize(widthCandidate: 120, heightCandidate: 40, environment: [:])
        XCTAssertEqual(size.width, 120)
        XCTAssertEqual(size.height, 40)
    }

    func testNormalizeFallsBackToEnvironmentWhenWinsizeMissing() {
        let size = TUITerminalSizing.normalize(
            widthCandidate: nil,
            heightCandidate: nil,
            environment: ["COLUMNS": "132", "LINES": "33"]
        )
        XCTAssertEqual(size.width, 132)
        XCTAssertEqual(size.height, 33)
    }

    func testNormalizeFallsBackToDefaultsWhenNoUsableValue() {
        let size = TUITerminalSizing.normalize(
            widthCandidate: 0,
            heightCandidate: 0,
            environment: ["COLUMNS": "x", "LINES": "-1"]
        )
        XCTAssertEqual(size.width, 80)
        XCTAssertEqual(size.height, 24)
    }
}
