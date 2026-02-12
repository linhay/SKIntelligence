import XCTest
@testable import SKIACP
@testable import SKIACPAgent
@testable import SKIJSONRPC
@testable import SKIntelligence

final class ACPPermissionPolicyTests: XCTestCase {
    func testPolicyAllowModeBypassesRequester() async throws {
        let requester = PermissionRequesterMock(response: .init(outcome: .cancelled))
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .allow,
            requester: { params in try await requester.request(params) }
        )

        let result = try await policy.evaluate(sampleRequest(sessionId: "sess-allow"))
        XCTAssertEqual(result.outcome, .selected(.init(optionId: "allow_once")))
        let calls = await requester.getCalls()
        XCTAssertEqual(calls, 0)
    }

    func testPolicyDenyModeBypassesRequester() async throws {
        let requester = PermissionRequesterMock(response: .init(outcome: .selected(.init(optionId: "allow_once"))))
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .deny,
            requester: { params in try await requester.request(params) }
        )

        let result = try await policy.evaluate(sampleRequest(sessionId: "sess-deny"))
        XCTAssertEqual(result.outcome, .cancelled)
        let calls = await requester.getCalls()
        XCTAssertEqual(calls, 0)
    }

    func testPolicyAskModeUsesRequesterThenRemembersAlways() async throws {
        let requester = PermissionRequesterMock(response: .init(outcome: .selected(.init(optionId: "allow_always"))))
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .ask,
            requester: { params in try await requester.request(params) }
        )
        let request = sampleRequest(sessionId: "sess-ask")

        let first = try await policy.evaluate(request)
        await policy.remember(request, decision: first)
        let firstCalls = await requester.getCalls()
        XCTAssertEqual(firstCalls, 1)

        let second = try await policy.evaluate(request)
        XCTAssertEqual(second.outcome, .selected(.init(optionId: "allow_always")))
        let secondCalls = await requester.getCalls()
        XCTAssertEqual(secondCalls, 1)
    }

    func testPolicyAskRequiredPropagatesBridgeError() async throws {
        let requester = PermissionRequesterMock(error: ACPPermissionRequestBridgeError.requestTimeout)
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .ask,
            allowOnBridgeError: false,
            requester: { params in try await requester.request(params) }
        )

        do {
            _ = try await policy.evaluate(sampleRequest(sessionId: "sess-required"))
            XCTFail("Expected bridge error")
        } catch let error as ACPPermissionRequestBridgeError {
            XCTAssertEqual(error, .requestTimeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPolicyAskPermissiveFallsBackToAllowOnBridgeError() async throws {
        let requester = PermissionRequesterMock(error: ACPPermissionRequestBridgeError.requestTimeout)
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .ask,
            allowOnBridgeError: true,
            requester: { params in try await requester.request(params) }
        )

        let result = try await policy.evaluate(sampleRequest(sessionId: "sess-permissive"))
        XCTAssertEqual(result.outcome, .selected(.init(optionId: "allow_once")))
    }

    func testDeleteClearsPermissionMemoryViaService() async throws {
        let requester = PermissionRequesterMock(response: .init(outcome: .selected(.init(optionId: "allow_always"))))
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .ask,
            requester: { params in try await requester.request(params) }
        )
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoPermissionPolicyClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(sessionCapabilities: .init(delete: .init()), loadSession: true),
            permissionPolicy: policy,
            notificationSink: { _ in }
        )

        let newResp = await service.handle(.init(
            id: .int(1),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        ))
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        _ = await service.handle(.init(
            id: .int(2),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("remember")]))
        ))
        let promptCalls = await requester.getCalls()
        XCTAssertEqual(promptCalls, 1)

        _ = await service.handle(.init(
            id: .int(3),
            method: ACPMethods.sessionDelete,
            params: try ACPCodec.encodeParams(ACPSessionDeleteParams(sessionId: session.sessionId))
        ))

        await requester.setError(ACPPermissionRequestBridgeError.requestTimeout)
        do {
            _ = try await policy.evaluate(sampleRequest(sessionId: session.sessionId))
            XCTFail("Expected memory cleared and requester error to propagate")
        } catch let error as ACPPermissionRequestBridgeError {
            XCTAssertEqual(error, .requestTimeout)
        }
    }

    func testLogoutClearsPermissionMemoryViaService() async throws {
        let requester = PermissionRequesterMock(response: .init(outcome: .selected(.init(optionId: "allow_always"))))
        let policy = ACPBridgeBackedPermissionPolicy(
            mode: .ask,
            requester: { params in try await requester.request(params) }
        )
        let service = ACPAgentService(
            sessionFactory: { SKILanguageModelSession(client: EchoPermissionPolicyClient()) },
            agentInfo: .init(name: "ski", version: "0.1.0"),
            capabilities: .init(authCapabilities: .init(logout: .init()), loadSession: true),
            permissionPolicy: policy,
            notificationSink: { _ in }
        )

        let newResp = await service.handle(.init(
            id: .int(11),
            method: ACPMethods.sessionNew,
            params: try ACPCodec.encodeParams(ACPSessionNewParams(cwd: "/tmp"))
        ))
        let session = try ACPCodec.decodeResult(newResp.result, as: ACPSessionNewResult.self)

        _ = await service.handle(.init(
            id: .int(12),
            method: ACPMethods.sessionPrompt,
            params: try ACPCodec.encodeParams(ACPSessionPromptParams(sessionId: session.sessionId, prompt: [.text("remember")]))
        ))
        let promptCalls = await requester.getCalls()
        XCTAssertEqual(promptCalls, 1)

        _ = await service.handle(.init(
            id: .int(13),
            method: ACPMethods.logout,
            params: try ACPCodec.encodeParams(ACPLogoutParams())
        ))

        await requester.setError(ACPPermissionRequestBridgeError.requestTimeout)
        do {
            _ = try await policy.evaluate(sampleRequest(sessionId: session.sessionId))
            XCTFail("Expected memory cleared and requester error to propagate")
        } catch let error as ACPPermissionRequestBridgeError {
            XCTAssertEqual(error, .requestTimeout)
        }
    }

    private func sampleRequest(sessionId: String) -> ACPSessionPermissionRequestParams {
        ACPSessionPermissionRequestParams(
            sessionId: sessionId,
            toolCall: .init(
                toolCallId: "call-1",
                title: "Execute session prompt",
                kind: .execute,
                locations: [.init(path: "/tmp")],
                rawInput: .object(["command": .string("ls -la")])
            ),
            options: [
                .init(optionId: "allow_once", name: "Allow once", kind: .allowOnce),
                .init(optionId: "allow_always", name: "Always allow", kind: .allowAlways),
                .init(optionId: "reject_once", name: "Reject once", kind: .rejectOnce),
                .init(optionId: "reject_always", name: "Always reject", kind: .rejectAlways),
            ]
        )
    }
}

private actor PermissionRequesterMock {
    private(set) var calls: Int = 0
    private var response: ACPSessionPermissionRequestResult
    private var error: Error?

    init(response: ACPSessionPermissionRequestResult) {
        self.response = response
    }

    init(error: Error) {
        self.response = .init(outcome: .cancelled)
        self.error = error
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    func request(_ params: ACPSessionPermissionRequestParams) throws -> ACPSessionPermissionRequestResult {
        _ = params
        calls += 1
        if let error {
            throw error
        }
        return response
    }

    func getCalls() -> Int {
        calls
    }
}

private struct EchoPermissionPolicyClient: SKILanguageModelClient {
    func respond(_ body: ChatRequestBody) async throws -> sending SKIResponse<ChatResponseBody> {
        let text = body.messages.compactMap { message -> String? in
            if case .user(let content, _) = message, case .text(let value) = content {
                return value
            }
            return nil
        }.joined(separator: "\n")

        let payload = """
        {
          "choices": [
            {
              "finish_reason": "stop",
              "message": {
                "content": "echo: \(text)",
                "role": "assistant"
              }
            }
          ],
          "created": 0,
          "model": "test"
        }
        """

        return try SKIResponse<ChatResponseBody>(
            httpResponse: .init(status: .ok),
            data: Data(payload.utf8)
        )
    }
}
