import Foundation
import XCTest

final class ACPSpecCoverageMatrixTests: XCTestCase {
    func testCoverageMatrixReferencesExistingTests() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let matrixURL = root.appendingPathComponent("docs-dev/dev/ACP-Spec-Coverage-Matrix.md")
        let content = try String(contentsOf: matrixURL, encoding: .utf8)

        let testIDRegex = try NSRegularExpression(
            pattern: #"SKIntelligenceTests\.([A-Za-z0-9_]+)/(test[A-Za-z0-9_]+)"#
        )
        let ns = content as NSString
        let matches = testIDRegex.matches(in: content, range: NSRange(location: 0, length: ns.length))
        XCTAssertFalse(matches.isEmpty, "Expected at least one test reference in matrix")

        let testsDir = root.appendingPathComponent("Tests/SKIntelligenceTests")
        for match in matches {
            let className = ns.substring(with: match.range(at: 1))
            let methodName = ns.substring(with: match.range(at: 2))
            let fileURL = testsDir.appendingPathComponent("\(className).swift")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Missing test file for \(className)")

            let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(
                fileContent.contains("func \(methodName)"),
                "Missing test method \(methodName) in \(fileURL.lastPathComponent)"
            )
        }
    }

    func testCoverageMatrixReferencedFilesExist() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let matrixURL = root.appendingPathComponent("docs-dev/dev/ACP-Spec-Coverage-Matrix.md")
        let content = try String(contentsOf: matrixURL, encoding: .utf8)

        let fileRegex = try NSRegularExpression(
            pattern: #"Tests/SKIntelligenceTests/[A-Za-z0-9_]+\.swift"#
        )
        let ns = content as NSString
        let matches = fileRegex.matches(in: content, range: NSRange(location: 0, length: ns.length))

        for match in matches {
            let relativePath = ns.substring(with: match.range)
            let fileURL = root.appendingPathComponent(relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Missing file path in matrix: \(relativePath)")
        }
    }
}
