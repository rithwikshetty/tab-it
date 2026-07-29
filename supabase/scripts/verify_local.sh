#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/supabase/scripts/assert_local_only.sh"

status_output="$(supabase status --workdir "$ROOT_DIR")"

required_endpoints=(
  "http://127.0.0.1:54321"
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
  "http://127.0.0.1:54323"
  "http://127.0.0.1:54324"
)

for endpoint in "${required_endpoints[@]}"; do
  if [[ "$status_output" != *"$endpoint"* ]]; then
    echo "[local-supabase] Expected local endpoint was not reported: $endpoint" >&2
    exit 1
  fi
done

if [[ "$status_output" == *".supabase.co"* ]]; then
  echo "[local-supabase] Refusing: status contained a hosted Supabase URL." >&2
  exit 1
fi

container_names="$(docker ps \
  --filter "label=com.supabase.cli.project=tab-local" \
  --format '{{.Names}}')"

if [[ -z "$container_names" ]]; then
  echo "[local-supabase] No running tab-local containers were found." >&2
  exit 1
fi

while IFS= read -r container_name; do
  if [[ "$container_name" != supabase_*_tab-local ]]; then
    echo "[local-supabase] Refusing: unexpected container $container_name." >&2
    exit 1
  fi
done <<<"$container_names"

echo "[local-supabase] Verified local API, database, Studio, email endpoints, and tab-local containers."
