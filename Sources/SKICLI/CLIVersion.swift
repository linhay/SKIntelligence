import Foundation

enum SKICLIVersion {
    static let fallback = "dev"

    static var current: String {
        detect(
            executablePath: CommandLine.arguments.first,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func detect(executablePath: String?, environment: [String: String]) -> String {
        if let envVersion = nonEmpty(environment["SKI_VERSION"]) {
            return envVersion
        }
        if let path = executablePath, let parsed = parseSidecarVersion(from: path) {
            return parsed
        }
        if let path = executablePath, let parsed = parseHomebrewCellarVersion(from: path) {
            return parsed
        }
        if let path = executablePath, let parsed = parseGitTagVersion(from: path) {
            return parsed
        }
        return fallback
    }

    private static func parseHomebrewCellarVersion(from executablePath: String) -> String? {
        let resolvedPath = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        let parts = resolvedPath.split(separator: "/").map(String.init)
        guard let cellarIndex = parts.firstIndex(of: "Cellar"),
              parts.indices.contains(cellarIndex + 2),
              parts[cellarIndex + 1] == "ski" else {
            return nil
        }
        return nonEmpty(parts[cellarIndex + 2])
    }

    private static func parseSidecarVersion(from executablePath: String) -> String? {
        let resolvedPath = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        let sidecarPath = resolvedPath + ".version"
        guard FileManager.default.fileExists(atPath: sidecarPath),
              let content = try? String(contentsOfFile: sidecarPath, encoding: .utf8) else {
            return nil
        }
        return nonEmpty(content)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func parseGitTagVersion(from executablePath: String) -> String? {
        let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        guard let repoRoot = findGitRepositoryRoot(startingAt: executableURL.deletingLastPathComponent()) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repoRoot.path, "describe", "--tags", "--abbrev=0"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed = nonEmpty(raw) {
                return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func findGitRepositoryRoot(startingAt start: URL) -> URL? {
        var current = start
        while true {
            let marker = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }
}
