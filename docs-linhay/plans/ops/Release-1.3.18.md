# Release 1.3.18

Date: 2026-02-28

## Summary
- Completed STJSON JSON-RPC migration in ACP path.
- Removed legacy `SKIJSONRPC` module implementation.
- Removed AnyCodable JSONValue-style compatibility sugar in ACP code.
- Consolidated docs/memory/release artifacts for migration closure.

## Included Commits
- `ae51e15` refactor(acp): remove AnyCodable JSONValue-style compat sugar
- `5a83e33` refactor(acp): migrate jsonrpc stack to STJSON and remove SKIJSONRPC
- `8e5931d` docs(acp): add STJSON JSONRPC migration spec and skills index
- `fb2034c` chore(skills): add skintelligence skill package and run scripts
- `a63ed59` docs(ops): add STJSON migration release note

## Validation
- Full test run:
  - `swift test --package-path .`
  - Result: `420 passed, 0 failed, 1 skipped`

## Release Links
- Tag: `1.3.18`
- GitHub Release: https://github.com/linhay/SKIntelligence/releases/tag/1.3.18

## Notes
- The skipped test is the live websocket reconnect opt-in case.
- Dynamic AnyCodable handling in ACP now uses explicit decode/value access instead of removed sugar APIs.
