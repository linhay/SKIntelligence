# Release 1.3.19

## Summary

This release delivers two major capabilities:

1. Session-level token usage tracking (prompt/completion/total/reasoning).
2. OpenAI client endpoint failover based on ordered `profiles` (`EndpointProfile`).

## Highlights

- Added `SKITokenUsageSnapshot` and session APIs:
  - `SKILanguageModelSession.tokenUsageSnapshot()`
  - `SKILanguageModelSession.resetTokenUsage()`
- Token usage aggregation now covers both non-streaming and streaming paths.
- `SKIAgentSession.stats()` now includes `tokenUsage`.
- Added `OpenAIClient.EndpointProfile` and ordered `profiles` fallback.
- Streaming fallback now retries next profile only before receiving the first chunk.
- Kept legacy `.url/.token/.model/fallbackURLs` APIs as deprecated compatibility shims.
- Migrated repository call sites to `profiles` to remove deprecated usage in tests/docs.

## Tests

- Full suite passed:
  - `429` executed
  - `0` failures
  - `1` skipped (opt-in live websocket reconnect)

## Notable Files

- `Sources/SKIntelligence/SKITokenUsageSnapshot.swift`
- `Sources/SKIntelligence/SKILanguageModelSession.swift`
- `Sources/SKIntelligence/SKIAgentSession.swift`
- `Sources/SKIClients/OpenAIClient.swift`
- `Tests/SKIntelligenceTests/SKITokenUsageTrackingTests.swift`
- `Tests/SKIntelligenceTests/OpenAIClientFallbackEndpointTests.swift`

## Tag

- `1.3.19`
