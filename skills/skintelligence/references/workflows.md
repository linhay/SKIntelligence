# SKIntelligence Workflows

## 1. ACP Feature / Compatibility Workflow

1. Define scenario and acceptance.
2. Add or update ACP tests (protocol/client/agent/transport/CLI process).
3. Run focused tests until red is confirmed.
4. Implement minimal fix.
5. Re-run focused tests for green.
6. Run ACP regression suite.
7. Update docs and memory.

Acceptance signals:
- Focused tests pass.
- ACP regression summary reports no required-stage failures.

## 2. Narrow Bugfix Workflow

1. Identify smallest failing test filter.
2. Reproduce with one command.
3. Patch minimal surface.
4. Re-run same filter.
5. Expand to nearby module filter if needed.

Acceptance signals:
- Original reproduction no longer fails.
- No new failures in neighboring tests.

## 3. codex-acp Integration Confidence Workflow

1. Verify prerequisites (`codex`, `npx`, login state).
2. Run connect smoke once.
3. If handshake fails, classify as env/tooling vs repo behavior.
4. Continue with local ACP suite for repository confidence.

Acceptance signals:
- At least one run yields `prompt_result` in JSON output.
- Or environment blocker is explicitly captured.

## 4. Docs and Memory Sync Workflow

1. Update feature/dev/ops docs based on change type.
2. Append decision/risk/milestone entry to `memory/YYYY-MM-DD.md`.
3. Run `qmd update && qmd embed`.
4. If qmd collection path is misconfigured, record risk and remediation.

Acceptance signals:
- Documents reflect new behavior.
- Memory entry is searchable.
