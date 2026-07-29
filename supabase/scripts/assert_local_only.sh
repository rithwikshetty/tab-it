#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_PATH="$ROOT_DIR/supabase/config.toml"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[local-supabase] Missing supabase/config.toml." >&2
  exit 1
fi

if ! grep -Eq '^project_id = "tab-local"$' "$CONFIG_PATH"; then
  echo "[local-supabase] Refusing: project_id must be exactly tab-local." >&2
  exit 1
fi

if [[ -e "$ROOT_DIR/supabase/.temp/project-ref" ]] ||
   [[ -e "$ROOT_DIR/supabase/.temp/linked-project.json" ]]; then
  echo "[local-supabase] Refusing: hosted-project link metadata is present." >&2
  exit 1
fi

if [[ -n "${SUPABASE_DB_URL:-}" ]] ||
   [[ -n "${SUPABASE_PROJECT_REF:-}" ]] ||
   [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "[local-supabase] Refusing: remote Supabase environment variables are set." >&2
  exit 1
fi

echo "[local-supabase] Local-only guard passed."
