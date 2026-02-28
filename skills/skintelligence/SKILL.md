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

## References

- Methods and acceptance flows: `references/workflows.md`
- Module-specific playbooks: `references/module-playbooks.md`
- High-frequency command patterns: `references/commands.md`
- Failure signatures and triage: `references/troubleshooting.md`

## Output and DoD

1. Acceptance scenarios satisfied.
2. Relevant tests passed, or blockers and risks explicitly stated.
3. Docs updated in correct location.
4. Key decisions and risks written to memory and re-indexed.
