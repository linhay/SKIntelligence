# Release Note - 2026-02-28 - STJSON JSON-RPC Migration

## Scope
- ACP JSON-RPC stack migrated to STJSON.
- Removed legacy `SKIJSONRPC` module from source tree.
- Removed AnyCodable JSONValue-style compatibility sugar in ACP path.

## Key Changes
- Use `STJSON.JSONRPC.*` as the single JSON-RPC model source in ACP.
- Keep `Sources/SKIACP/JSONRPCCompat.swift` as focused compatibility/codec layer only.
- Replace ACP dynamic JSON access with `AnyCodable(...)` + `decode(to:)` / `value`.
- Remove:
  - `Sources/SKIJSONRPC/JSONRPCCodec.swift`
  - `Sources/SKIJSONRPC/JSONRPCModels.swift`
  - `Sources/SKIJSONRPC/JSONValue.swift`
  - `Sources/SKIACP/AnyCodable+JSONValueCompat.swift`

## Validation
- Full regression executed:
  - `swift test --package-path .`
  - Result: `420 passed, 0 failed, 1 skipped` (live reconnect opt-in skip)

## Related Commits
- `ae51e15` refactor(acp): remove AnyCodable JSONValue-style compat sugar
- `5a83e33` refactor(acp): migrate jsonrpc stack to STJSON and remove SKIJSONRPC
- `8e5931d` docs(acp): add STJSON JSONRPC migration spec and skills index
- `fb2034c` chore(skills): add skintelligence skill package and run scripts

## Risk Notes
- ACP route-level dynamic numeric decoding now goes through explicit numeric conversion helpers.
- If any downstream integration relied on removed JSONValue-style sugar APIs, it must migrate to `AnyCodable(...)` and `decode(to:)`.
