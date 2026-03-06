import Foundation
import XCTest
@testable import SKICLI

final class CLIVersionTests: XCTestCase {
    func testDetectUsesEnvironmentOverrideFirst() {
        let value = SKICLIVersion.detect(
            executablePath: "/tmp/any/ski",
            environment: ["SKI_VERSION": "9.9.9-test"]
        )
        XCTAssertEqual(value, "9.9.9-test")
    }

    func testDetectUsesSidecarVersionFile() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ski-version-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binaryPath = tempDir.appendingPathComponent("ski").path
        FileManager.default.createFile(atPath: binaryPath, contents: Data(), attributes: nil)
        try "3.1.4-local\n".write(toFile: binaryPath + ".version", atomically: true, encoding: .utf8)

        let value = SKICLIVersion.detect(executablePath: binaryPath, environment: [:])
        XCTAssertEqual(value, "3.1.4-local")
    }

    func testDetectParsesHomebrewCellarPath() {
        let value = SKICLIVersion.detect(
            executablePath: "/opt/homebrew/Cellar/ski/2.0.7/bin/ski",
            environment: [:]
        )
        XCTAssertEqual(value, "2.0.7")
    }
}
