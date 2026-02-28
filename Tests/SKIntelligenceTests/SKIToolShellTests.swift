import XCTest
 import STJSON
 import SKIACP
@testable import SKITools
@testable import SKIntelligence

final class SKIToolShellTests: XCTestCase {
    func testShellRuntimeSupportFlagMatchesPlatform() {
#if canImport(SKProcessRunner)
        XCTAssertTrue(SKIToolShell.isRuntimeSupported)
#else
        XCTAssertFalse(SKIToolShell.isRuntimeSupported)
#endif
    }

    func testShellWithoutCommandOrScriptFailsValidation() async throws {
        let tool = SKIToolShell()
        do {
            _ = try await tool.call(.init(command: nil, script: nil))
            XCTFail("Expected invalid arguments error")
        } catch let error as SKIToolError {
            switch error {
            case .invalidArguments(let reason):
                XCTAssertTrue(reason.contains("Provide either `command` or `script`."))
            case .toolUnavailable:
                XCTAssertFalse(SKIToolShell.isRuntimeSupported)
            default:
                XCTFail("Unexpected SKIToolError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
