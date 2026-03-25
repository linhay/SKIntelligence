# Release 2.0.4 (GitHub Short)

## Summary

- `BREAKING CHANGE`: remove `ski tui` and default chat mode.
- `ski` now shows help by default.
- `ski acp serve` and `ski acp client ...` remain the supported CLI entrypoints.

## Changes

1. CLI behavior
   - `ski` no longer enters an interactive chat page.
   - `ski tui` has been removed from the command tree.
   - `ski --version` and `ski version` remain available.
2. Code removal
   - Removed `Sources/SKICLI/TUI.swift`.
   - Removed `TUIByteParserTests` and `TUITerminalSizingTests`.
3. Documentation
   - Updated README to describe the CLI as ACP service/client oriented.
   - Marked `CLI-TUI-Spec` as retired.
   - Updated install runbook validation steps for the new root command behavior.

## Validation

- CLI regression:
  - `swift test --filter SKICLIProcessTests/testRootCommandShowsHelp --filter SKICLIProcessTests/testRootHelpStillAccessible --filter SKICLIProcessTests/testTUICommandIsRemoved --filter CLIVersionTests --filter SKICLITests`
- ACP regression:
  - `swift test --filter ACPClientServiceTests --filter ACPAgentServiceTests --filter ACPTransportBaselineTests --filter ACPWebSocketRoundtripTests --filter ACPWebSocketPermissionRoundtripTests --filter ACPTransportConsistencyTests`
- Smoke:
  - `.build/debug/ski` shows help
  - `.build/debug/ski tui` returns `Unexpected argument 'tui'`
  - `.build/debug/ski acp serve --help`
  - `.build/debug/ski acp client --help`

## Upgrade Notes

1. If you previously used `ski` as an interactive chat entrypoint, switch to explicit ACP workflows.
2. Use `ski --help` to discover the supported service/client commands.
3. Any automation invoking `ski tui` must be updated.
