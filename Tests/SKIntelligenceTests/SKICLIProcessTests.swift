import Foundation
import XCTest

final class SKICLIProcessTests: XCTestCase {
    func testClientMissingEndpointExitCodeIs2() throws {
        let result = try runSKI(arguments: ["acp", "client", "connect", "--transport", "ws", "--prompt", "hi"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--endpoint is required for ws transport"))
    }

    func testClientUpstreamFailureExitCodeIs4() throws {
        let result = try runSKI(arguments: [
            "acp", "client", "connect",
            "--transport", "ws",
            "--endpoint", "ws://127.0.0.1:1",
            "--prompt", "hi"
        ])
        XCTAssertEqual(result.exitCode, 4)
        XCTAssertTrue(result.stderr.contains("Error:"), "stderr did not contain error summary: \(result.stderr)")
        XCTAssertFalse(
            result.stderr.contains("--endpoint is required for ws transport"),
            "stderr unexpectedly looked like validation error: \(result.stderr)"
        )
    }

    func testServeInvalidListenExitCodeIs2() throws {
        let result = try runSKI(arguments: ["acp", "serve", "--transport", "ws", "--listen", "invalid"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("--listen must be in host:port format with port in 1...65535"))
    }
}

private extension SKICLIProcessTests {
    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runSKI(arguments: [String]) throws -> ProcessResult {
        guard let skiURL = findSKIBinary() else {
            throw XCTSkip("ski binary not found under .build")
        }

        let process = Process()
        process.executableURL = skiURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    func findSKIBinary() -> URL? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            ".build/arm64-apple-macosx/debug/ski",
            ".build/x86_64-apple-macosx/debug/ski",
            ".build/debug/ski"
        ]
        for relative in candidates {
            let candidate = root.appendingPathComponent(relative)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
