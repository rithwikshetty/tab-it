#!/usr/bin/env bash
set -euo pipefail

# Runs every pgTAP suite in supabase/tests against the local Supabase stack.
# Each suite is transactional (begin … rollback) so the DB is left untouched.
# Usage: ./supabase/scripts/run_db_tests.sh [test-file …]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Deliberately do not source any environment file. The guard also refuses to
# run while hosted-project link metadata or remote environment variables exist.
"$ROOT_DIR/supabase/scripts/assert_local_only.sh"
"$ROOT_DIR/supabase/scripts/verify_local.sh"
DB_CONTAINER="supabase_db_tab-local"

files=("$@")
if [[ ${#files[@]} -eq 0 ]]; then
  files=(supabase/tests/[0-9]*.sql)
fi

bash supabase/tests/00_sql_assembly.sh

failures=0
for f in "${files[@]}"; do
  echo "── $f"
  out="$(docker exec -i "$DB_CONTAINER" psql \
    --username postgres \
    --dbname postgres \
    --set ON_ERROR_STOP=1 < "$f" 2>&1)" || {
      echo "$out"
      echo "FAIL (query error) - $f"
      failures=$((failures+1))
      continue
    }
  echo "$out"
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
