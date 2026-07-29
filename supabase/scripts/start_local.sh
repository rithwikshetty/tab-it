#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/supabase/scripts/assert_local_only.sh"

command -v docker >/dev/null 2>&1 || {
  echo "[local-supabase] Docker is required." >&2
  exit 1
}
command -v supabase >/dev/null 2>&1 || {
  echo "[local-supabase] Supabase CLI is required." >&2
  exit 1
}

supabase start --workdir "$ROOT_DIR"

"$ROOT_DIR/supabase/scripts/verify_local.sh"
