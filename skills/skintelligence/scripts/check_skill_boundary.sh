#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SKILL_ROOT="skills/skintelligence"

if [[ ! -d "$SKILL_ROOT" ]]; then
  echo "missing skill root: $SKILL_ROOT" >&2
  exit 2
fi

# Rule: skills must not reference docs-dev paths.
rg -n "docs-dev/" "$SKILL_ROOT" -S 2>/dev/null \
  | rg -v "scripts/check_skill_boundary.sh" \
  >/tmp/skill_boundary_violations.txt || true

if [[ -s /tmp/skill_boundary_violations.txt ]]; then
  echo "boundary violation: skills must not reference docs-dev" >&2
  cat /tmp/skill_boundary_violations.txt >&2
  exit 1
fi

# Informational check: docs-dev should have at least one forward reference to skill.
if ! rg -n "skills/skintelligence" docs-dev -S >/tmp/skill_boundary_forward_refs.txt 2>/dev/null; then
  echo "warning: no docs-dev -> skills/skintelligence forward references found" >&2
  exit 3
fi

echo "boundary check passed"
cat /tmp/skill_boundary_forward_refs.txt
