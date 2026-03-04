---
name: skintelligence
description: Build, test, debug, and evolve the SKIntelligence Swift library with a method-first workflow. Use when tasks involve ACP protocol/client/server/transport behavior, `ski acp` CLI flows, regression gating, focused Swift test execution, codex-acp smoke validation, or core module work in Streaming/Memory/MCP/TextIndex that must follow BDD+TDD plus docs/memory synchronization.
---

# SKIntelligence

## Overview
Execute SKIntelligence engineering tasks with repeatable workflows and command wrappers.
Prefer method-driven execution: define acceptance first, run failing tests, implement minimal changes, run targeted/full regression, then sync docs and memory.

## Workflow Decision Tree

1. If task is ACP compatibility, transport routing, or `ski acp` behavior:
- Run `scripts/run_acp_regression.sh` first for baseline.
- Use targeted tests to isolate failures.
- Re-run regression after fixes.

2. If task is non-ACP module work (Streaming/Memory/MCP/TextIndex):
- Run `scripts/run_library_smoke.sh` first.
- Use `scripts/run_targeted_tests.sh <filter...>` for narrow red/green cycles.

3. If task is codex-acp integration or external handshake confidence:
- Run `scripts/run_codex_connect_smoke.sh [prompt]`.
- If unavailable, treat as environment constraint and continue local ACP validation.

4. If task changes protocol behavior or CLI contract:
- Require both focused tests and ACP regression suite before completion.
- Update docs and memory with decisions and risks.

5. If task requires MLX real-model determinism validation:
- Run `scripts/mlx_e2e_prepare.sh --run --model-id <model>` for one-command prepare + execute.
- Keep `MLX_E2E_TEMPERATURE=0` unless intentionally testing sampling variance.
- If skipped due to missing metallib, follow the repository MLX E2E ops runbook.

6. If task is release orchestration (especially major release):
- Build release notes under the repository release-note location (`Release-<version>.md`).
- Require full regression (`swift test --package-path .`) before tagging.
- Include migration notes for behavioral changes (CLI validation, stop-sequence semantics, ACP session model reuse).
- Provide release-day command block (`tag`, `push`, optional `gh release create`).

## Execution Standard

1. Define BDD acceptance in task language before coding.
2. Add/update tests first and confirm red.
3. Implement minimal code for green.
4. Refactor without behavior drift.
5. Sync docs and memory.

## Command Wrappers

- ACP regression:
```bash
skills/skintelligence/scripts/run_acp_regression.sh
skills/skintelligence/scripts/run_acp_regression.sh --with-codex
skills/skintelligence/scripts/run_acp_regression.sh --with-codex --strict-codex
```

- Core library smoke:
```bash
skills/skintelligence/scripts/run_library_smoke.sh
```

- Boundary guard:
```bash
skills/skintelligence/scripts/check_skill_boundary.sh
```

- Targeted tests:
```bash
skills/skintelligence/scripts/run_targeted_tests.sh ACPProtocolConformanceTests
skills/skintelligence/scripts/run_targeted_tests.sh ACPAgentServiceTests SKICLIProcessTests
skills/skintelligence/scripts/run_targeted_tests.sh SKIStreamingTests SKIMemoryTests
```

- codex-acp smoke:
```bash
skills/skintelligence/scripts/run_codex_connect_smoke.sh
skills/skintelligence/scripts/run_codex_connect_smoke.sh "hello from skintelligence"
```

- MLX real-model E2E:
```bash
scripts/mlx_e2e_prepare.sh --model-id mlx-community/Qwen2.5-0.5B-4bit
scripts/mlx_e2e_prepare.sh --run --model-id mlx-community/Qwen2.5-0.5B-4bit --timeout-seconds 120 --temperature 0
```

- Major release checklist:
```bash
swift test --package-path .
swift build -c release
git status --short
git tag --sort=-v:refname | head -n 5
git tag <major.minor.patch>
git push origin <major.minor.patch>
gh release create <major.minor.patch> --title "SKIntelligence <major.minor.patch>" --notes-file <release-note-path>
```

## References

- Methods and acceptance flows: `references/workflows.md`
- Module-specific playbooks: `references/module-playbooks.md`
- High-frequency command patterns: `references/commands.md`
- Failure signatures and triage: `references/troubleshooting.md`
- MLX runtime/E2E ops: repository MLX E2E runbook
- Major release baseline: repository major-release note

## Output and DoD

1. Acceptance scenarios satisfied.
2. Relevant tests passed, or blockers and risks explicitly stated.
3. Docs updated in correct location.
4. Key decisions and risks written to memory and re-indexed.
