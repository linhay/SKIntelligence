import XCTest
import Foundation

@testable import SKIMLXClient
@testable import SKIntelligence

#if canImport(MLXLMCommon)
import MLXLMCommon

final class MLXClientDeterminismE2ETests: XCTestCase {
    func testSameSeedProducesDeterministicOutput() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RUN_MLX_E2E_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_MLX_E2E_TESTS=1 to enable MLX real-model E2E tests.")
        }
        guard let modelID = env["MLX_E2E_MODEL_ID"], !modelID.isEmpty else {
            throw XCTSkip("Set MLX_E2E_MODEL_ID to run MLX real-model E2E tests.")
        }
        guard hasAnyMetalLibraryForRuntime(env: env) else {
            throw XCTSkip("No Metal library (*.metallib) found in runtime search paths. MLX runtime is unavailable in current environment.")
        }

        let revision = env["MLX_E2E_MODEL_REVISION"] ?? "main"
        let prompt = env["MLX_E2E_PROMPT"] ?? "Write one short sentence about Swift."
        let timeoutSeconds = env["MLX_E2E_REQUEST_TIMEOUT_SECONDS"]
            .flatMap(Double.init) ?? 180
        let temperature = env["MLX_E2E_TEMPERATURE"]
            .flatMap(Double.init) ?? 0

        let client = MLXClient(
            configuration: .init(
                modelID: modelID,
                revision: revision,
                requestTimeout: timeoutSeconds
            )
        )

        let body = ChatRequestBody(
            messages: [.user(content: .text(prompt))],
            maxCompletionTokens: 24,
            seed: 42,
            temperature: temperature
        )

        let first: String
        let second: String
        do {
            first = try await client.respond(body).content.choices.first?.message.content ?? ""
            second = try await client.respond(body).content.choices.first?.message.content ?? ""
        } catch let error as ModelFactoryError {
            if case .noModelFactoryAvailable = error {
                throw XCTSkip("MLX model factory unavailable in current runtime: \(error.localizedDescription)")
            }
            throw error
        } catch MLXClientError.requestTimedOut(let seconds) {
            throw XCTSkip("MLX E2E request timed out after \(seconds)s. Increase MLX_E2E_REQUEST_TIMEOUT_SECONDS if needed.")
        }

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second, "Expected deterministic output for same seed.")
    }

    func testQwenVLCanDescribeImageFromURL() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RUN_MLX_E2E_VL_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_MLX_E2E_VL_TESTS=1 to enable MLX VLM image E2E tests.")
        }
        guard let modelID = env["MLX_E2E_MODEL_ID"], !modelID.isEmpty else {
            throw XCTSkip("Set MLX_E2E_MODEL_ID to run MLX VLM image E2E tests.")
        }
        guard hasAnyMetalLibraryForRuntime(env: env) else {
            throw XCTSkip("No Metal library (*.metallib) found in runtime search paths. MLX runtime is unavailable in current environment.")
        }

        let revision = env["MLX_E2E_MODEL_REVISION"] ?? "main"
        let prompt = env["MLX_E2E_VL_PROMPT"] ?? "Describe this image in one short sentence."
        let timeoutSeconds = env["MLX_E2E_REQUEST_TIMEOUT_SECONDS"]
            .flatMap(Double.init) ?? 180
        let temperature = env["MLX_E2E_TEMPERATURE"]
            .flatMap(Double.init) ?? 0
        let imageURLString = env["MLX_E2E_VL_IMAGE_URL"] ?? "https://upload.wikimedia.org/wikipedia/commons/3/3a/Cat03.jpg"
        guard let imageURL = URL(string: imageURLString) else {
            throw XCTSkip("Invalid MLX_E2E_VL_IMAGE_URL: \(imageURLString)")
        }

        let client = MLXClient(
            configuration: .init(
                modelID: modelID,
                revision: revision,
                requestTimeout: timeoutSeconds
            )
        )

        let body = ChatRequestBody(
            messages: [
                .user(content: .parts([
                    .text(prompt),
                    .imageURL(imageURL),
                ]))
            ],
            maxCompletionTokens: 64,
            temperature: temperature
        )

        let output: String
        do {
            output = try await client.respond(body).content.choices.first?.message.content ?? ""
        } catch let error as ModelFactoryError {
            if case .noModelFactoryAvailable = error {
                throw XCTSkip("MLX model factory unavailable in current runtime: \(error.localizedDescription)")
            }
            throw error
        } catch MLXClientError.requestTimedOut(let seconds) {
            throw XCTSkip("MLX VLM E2E request timed out after \(seconds)s. Increase MLX_E2E_REQUEST_TIMEOUT_SECONDS if needed.")
        }

        print("MLX_E2E_VL_OUTPUT: \(output)")
        XCTAssertFalse(output.isEmpty, "Expected non-empty description for image input.")
    }

    private func hasAnyMetalLibraryForRuntime(env: [String: String]) -> Bool {
        var candidateDirs = [URL]()
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidateDirs.append(root)
        candidateDirs.append(root.appendingPathComponent(".build", isDirectory: true))

        if let dyldFrameworkPath = env["DYLD_FRAMEWORK_PATH"], !dyldFrameworkPath.isEmpty {
            for raw in dyldFrameworkPath.split(separator: ":") {
                candidateDirs.append(URL(fileURLWithPath: String(raw), isDirectory: true))
            }
        }
        if let metallibDir = env["MLX_E2E_METALLIB_DIR"], !metallibDir.isEmpty {
            candidateDirs.append(URL(fileURLWithPath: metallibDir, isDirectory: true))
        }

        for directory in candidateDirs {
            if containsMetalLibrary(in: directory) {
                return true
            }
        }
        return false
    }

    private func containsMetalLibrary(in directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "metallib" else { continue }
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return true
            }
        }
        return false
    }
}
#endif
