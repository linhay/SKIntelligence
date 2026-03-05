import Foundation
import XCTest

final class CLIDistributionScriptsTests: XCTestCase {
    func testInstallScriptExistsAndReferencesLatestReleaseAPI() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scriptURL = root.appendingPathComponent("scripts/install_ski.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), "missing install script at \(scriptURL.path)")
        let content = try String(contentsOf: scriptURL)
        XCTAssertTrue(content.contains("/releases/latest"), "install script should resolve latest release")
        XCTAssertTrue(content.contains("ski-macos-"), "install script should target macOS binary assets")
    }

    func testPackageScriptExistsAndProducesMacOSAssetNames() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scriptURL = root.appendingPathComponent("scripts/package_cli.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), "missing package script at \(scriptURL.path)")
        let content = try String(contentsOf: scriptURL)
        XCTAssertTrue(content.contains("ski-macos-arm64.tar.gz"))
        XCTAssertTrue(content.contains("ski-macos-x86_64.tar.gz"))
    }

    func testReleaseScriptIncludesCLIPackagingAndAssetUpload() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scriptURL = root.appendingPathComponent("scripts/release_major.sh")
        let content = try String(contentsOf: scriptURL)
        XCTAssertTrue(content.contains("scripts/package_cli.sh"))
        XCTAssertTrue(content.contains("dist/cli"))
        XCTAssertTrue(content.contains("gh release create"))
        XCTAssertTrue(content.contains("ski-macos-"))
    }

    func testHomebrewFormulaGeneratorScriptExistsAndTargetsReleaseAssets() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scriptURL = root.appendingPathComponent("scripts/generate_homebrew_formula.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), "missing script at \(scriptURL.path)")
        let content = try String(contentsOf: scriptURL)
        XCTAssertTrue(content.contains("ski-macos-arm64.tar.gz"))
        XCTAssertTrue(content.contains("ski-macos-x86_64.tar.gz"))
        XCTAssertTrue(content.contains("class Ski < Formula"))
    }

    func testReleaseScriptIncludesHomebrewFormulaGeneration() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scriptURL = root.appendingPathComponent("scripts/release_major.sh")
        let content = try String(contentsOf: scriptURL)
        XCTAssertTrue(content.contains("RUN_HOMEBREW_FORMULA"))
        XCTAssertTrue(content.contains("scripts/generate_homebrew_formula.sh"))
        XCTAssertTrue(content.contains("dist/homebrew"))
    }

    func testReadmeMentionsHomebrewInstall() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readmeURL = root.appendingPathComponent("README.md")
        let content = try String(contentsOf: readmeURL)
        XCTAssertTrue(content.contains("brew install"))
        XCTAssertTrue(content.contains("Homebrew"))
        XCTAssertTrue(content.contains("brew tap"))
        XCTAssertTrue(content.contains("brew install linhay/tap/ski"))
    }

    func testRepositoryContainsFormulaSki() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let formulaURL = root.appendingPathComponent("Formula/ski.rb")
        XCTAssertTrue(FileManager.default.fileExists(atPath: formulaURL.path), "missing formula at \(formulaURL.path)")
        let content = try String(contentsOf: formulaURL)
        XCTAssertTrue(content.contains("class Ski < Formula"))
        XCTAssertTrue(content.contains("on_macos do"))
        XCTAssertTrue(content.contains("on_arm do"))
        XCTAssertTrue(content.contains("on_intel do"))
        XCTAssertTrue(content.contains("ski-macos-arm64.tar.gz"))
        XCTAssertTrue(content.contains("ski-macos-x86_64.tar.gz"))
        XCTAssertFalse(content.contains("depends_on \"swift\" => :build"))
        XCTAssertFalse(content.contains("system \"swift\", \"build\""))
    }

    func testReleaseScriptSupportsExportingTapFormula() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scriptURL = root.appendingPathComponent("scripts/release_major.sh")
        let content = try String(contentsOf: scriptURL)
        XCTAssertTrue(content.contains("EXPORT_FORMULA_TO_REPO"))
        XCTAssertTrue(content.contains("Formula/ski.rb"))
    }

    func testDistributionScriptsPassBashSyntaxCheck() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scripts = [
            root.appendingPathComponent("scripts/install_ski.sh").path,
            root.appendingPathComponent("scripts/package_cli.sh").path,
            root.appendingPathComponent("scripts/generate_homebrew_formula.sh").path,
            root.appendingPathComponent("scripts/sync_homebrew_tap.sh").path,
            root.appendingPathComponent("scripts/release_major.sh").path
        ]
        for script in scripts {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-n", script]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "bash -n failed for \(script)")
        }
    }
}
