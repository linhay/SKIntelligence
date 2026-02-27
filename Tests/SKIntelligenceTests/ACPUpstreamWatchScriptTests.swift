import Foundation
import XCTest

final class ACPUpstreamWatchScriptTests: XCTestCase {
    func testWatchReportIncludesPriorityItemsAndSupportsRepoOverride() throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let output = workspace.appendingPathComponent("acp-upstream-daily.md")
        let bin = workspace.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let root = projectRoot()
        try installMockCurl(into: bin, root: root)
        try installMockGH(into: bin, withPRPayload: true)

        let result = try runWatchScript(
            root: root,
            environment: [
                "ACP_UPSTREAM_REPOS": "testorg/spec",
                "ACP_UPSTREAM_SKIP_ORG_SCAN": "1",
                "ACP_UPSTREAM_DAILY_FILE": output.path,
                "ACP_UPSTREAM_SINCE_DAYS": "1",
                "PATH": "\(bin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stderr=\(result.stderr)")
        let report = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(report.contains("Repositories Watched: 1"))
        XCTAssertTrue(report.contains("## Priority Items"), "report=\n\(report)")
        XCTAssertTrue(report.contains("- Level: P0"), "report=\n\(report)")
        XCTAssertTrue(report.contains("https://github.com/testorg/spec/pull/42"), "report=\n\(report)")
    }

    func testWatchReportShowsNoneWhenNoPriorityItems() throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let output = workspace.appendingPathComponent("acp-upstream-daily.md")
        let bin = workspace.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let root = projectRoot()
        try installMockCurl(into: bin, root: root)
        try installMockGH(into: bin, withPRPayload: false)

        let result = try runWatchScript(
            root: root,
            environment: [
                "ACP_UPSTREAM_REPOS": "testorg/spec",
                "ACP_UPSTREAM_SKIP_ORG_SCAN": "1",
                "ACP_UPSTREAM_DAILY_FILE": output.path,
                "ACP_UPSTREAM_SINCE_DAYS": "1",
                "PATH": "\(bin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stderr=\(result.stderr)")
        let report = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(report.contains("## Priority Items"), "report=\n\(report)")
        XCTAssertTrue(report.contains("- none"), "report=\n\(report)")
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acp-watch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    private func installMockCurl(into bin: URL, root: URL) throws {
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail
        out=""
        url=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -o) out="$2"; shift 2;;
            *) url="$1"; shift;;
          esac
        done
        if [[ "$url" == *"meta.unstable.json" ]]; then
          cat "\(root.path)/Tests/SKIntelligenceTests/Fixtures/acp-schema-meta/meta.unstable.json" > "$out"
        else
          cat "\(root.path)/Tests/SKIntelligenceTests/Fixtures/acp-schema-meta/meta.json" > "$out"
        fi
        """
        try writeExecutable(script, to: bin.appendingPathComponent("curl"))
    }

    private func installMockGH(into bin: URL, withPRPayload: Bool) throws {
        let prs: String
        if withPRPayload {
            prs = """
            [
              {
                "title": "breaking: adjust transport contract",
                "body": "protocol update",
                "updated_at": "2026-02-27T00:00:00Z",
                "html_url": "https://github.com/testorg/spec/pull/42"
              }
            ]
            """
        } else {
            prs = "[]"
        }
        let script = """
        #!/usr/bin/env bash
        set -eo pipefail
        if [ "${1:-}" != "api" ]; then
          echo "{}"
          exit 0
        fi
        args="$*"
        case "$args" in
          *"/repos/testorg/spec/pulls?state=all&sort=updated&direction=desc&per_page=20"*)
            cat <<'JSON'
        \(prs)
        JSON
            ;;
          *"/repos/testorg/spec/issues?state=all&sort=updated&direction=desc&per_page=20"*)
            echo '[]'
            ;;
          *"/repos/testorg/spec/commits/main"*)
            echo '{"sha":"abcdef1234567890"}'
            ;;
          *"/repos/testorg/spec/releases/latest"*)
            echo '{"tag_name":"v0.1.0","published_at":"2026-02-27T00:00:00Z"}'
            ;;
          *"/repos/testorg/spec"*)
            cat <<'JSON'
        {"default_branch":"main","pushed_at":"2026-02-27T00:00:00Z","html_url":"https://github.com/testorg/spec"}
        JSON
            ;;
          *)
            echo '[]'
            ;;
        esac
        """
        try writeExecutable(script, to: bin.appendingPathComponent("gh"))
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func runWatchScript(root: URL, environment: [String: String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = root.appendingPathComponent("scripts/acp_upstream_watch.sh")
        process.arguments = []
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
