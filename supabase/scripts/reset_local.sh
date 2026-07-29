#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/supabase/scripts/assert_local_only.sh"

supabase db reset \
  --workdir "$ROOT_DIR" \
  --local

"$ROOT_DIR/supabase/scripts/verify_local.sh"
