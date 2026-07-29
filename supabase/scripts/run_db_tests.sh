#!/usr/bin/env bash
set -euo pipefail

# Runs every pgTAP suite in supabase/tests against the local Supabase stack.
# Each suite is transactional (begin … rollback) so the DB is left untouched.
# Usage: ./supabase/scripts/run_db_tests.sh [test-file …]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Deliberately do not source .env.local and do not use --linked. Database tests
# must never fall back to the production project.
SUPABASE_CMD=(npx --yes supabase db query --workdir "$ROOT_DIR" --local)

files=("$@")
if [[ ${#files[@]} -eq 0 ]]; then
  files=(supabase/tests/[0-9]*.sql)
fi

bash supabase/tests/00_sql_assembly.sh

failures=0
for f in "${files[@]}"; do
  echo "── $f"
  out="$("${SUPABASE_CMD[@]}" -f "$f" 2>&1)" || { echo "$out"; echo "FAIL (query error) - $f"; failures=$((failures+1)); continue; }
  echo "$out" | grep -o '"line":"[^"]*"' | sed 's/"line":"//; s/"$//' | sed 's/\\"/"/g' || true
  if echo "$out" | grep -q 'not ok'; then
    echo "FAIL - $f"
    failures=$((failures+1))
  else
    echo "ok - $f"
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "✗ $failures suite(s) failed"
  exit 1
fi
echo "✓ all pgTAP suites passed"
