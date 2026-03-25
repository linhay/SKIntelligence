# SKIntelligence Module Playbooks

## Streaming (`SKIResponseStream`)

When to use:
- Streaming output regressions.
- Chunk ordering or tool-call aggregation issues.

Method:
1. Reproduce with `SKIStreamingTests`.
2. Validate delta aggregation boundaries.
3. Confirm non-streaming path is unaffected.

Acceptance:
- Streaming tests pass.
- No regression in related response decoding tests.

## Memory (`SKIConversationMemory` / `SKISummaryMemory`)

When to use:
- Context retention drifts.
- Summary or memory store persistence behavior changes.

Method:
1. Run `SKIMemoryTests`.
2. Validate store abstraction contract (`SKIMemoryStore`).
3. Validate summary generation and retrieval behavior.

Acceptance:
- Memory tests pass.
- Behavior documented when retention policy changes.

## MCP (`SKIMCPManager` / `SKIMCPClient`)

When to use:
- MCP server registration or tool listing failures.
- Connection lifecycle regressions.

Method:
1. Run `SKIMCPIntegrationTests`.
2. Verify register/unregister lifecycle.
3. Verify tool aggregation behavior.

Acceptance:
- Integration tests pass.
- Failure mode is diagnosable from logs/errors.

## Text Index / CLIP (`SKITextIndex`, `SKIClip`)

When to use:
- Similarity or indexing accuracy/performance regressions.
- Platform-specific compile/runtime behavior in CLIP code.

Method:
1. Run `SKITextIndexTests` first.
2. Run performance tests only when required by change scope.
3. Keep CoreML/platform guards intact.

Acceptance:
- Index tests pass.
- Performance delta explained when benchmark-sensitive logic changed.
