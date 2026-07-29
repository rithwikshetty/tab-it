#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUCKET="${SUPABASE_RECEIPTS_BUCKET:-receipts}"

usage() {
  cat <<'EOF'
Delete receipt storage from an explicitly confirmed non-production project.

Usage:
  TAB_CONFIRM_NONPRODUCTION_STORAGE=1 \
    SUPABASE_PROJECT_REF=<non-production-ref> \
    SUPABASE_SERVICE_ROLE_KEY=<non-production-key> \
    ./supabase/scripts/clear_receipts_storage.sh [--delete-bucket]

Behavior:
  - Calls the Supabase Storage API to empty the receipts bucket.
  - With --delete-bucket, deletes the empty bucket too.
  - Refuses to run without an explicit non-production confirmation, project
    ref, and service-role key. There is no linked-project fallback.

Environment variables:
  TAB_CONFIRM_NONPRODUCTION_STORAGE  Must equal 1.
  SUPABASE_SERVICE_ROLE_KEY          Required non-production service-role key.
  SUPABASE_PROJECT_REF               Required non-production project ref.
  SUPABASE_RECEIPTS_BUCKET   Optional bucket name (defaults to receipts).
EOF
}

DELETE_BUCKET=false
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ "${1:-}" == "--delete-bucket" ]]; then
  DELETE_BUCKET=true
elif [[ -n "${1:-}" ]]; then
  usage
  exit 2
fi

cd "$ROOT_DIR"

if [[ "${TAB_CONFIRM_NONPRODUCTION_STORAGE:-}" != "1" ]]; then
  echo "[storage-cleanup] Refusing to run: set TAB_CONFIRM_NONPRODUCTION_STORAGE=1 for an isolated non-production project." >&2
  exit 1
fi

if [[ -z "${SUPABASE_PROJECT_REF:-}" || -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "[storage-cleanup] SUPABASE_PROJECT_REF and SUPABASE_SERVICE_ROLE_KEY are required." >&2
  exit 1
fi

PROJECT_REF="$SUPABASE_PROJECT_REF"
BASE_URL="https://${PROJECT_REF}.supabase.co/storage/v1"
AUTH_HEADER="Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}"
APIKEY_HEADER="apikey: ${SUPABASE_SERVICE_ROLE_KEY}"

echo "[storage-cleanup] Emptying bucket ${BUCKET} in confirmed non-production project ${PROJECT_REF}"
curl --fail --silent --show-error \
  --request POST \
  --header "$AUTH_HEADER" \
  --header "$APIKEY_HEADER" \
  "${BASE_URL}/bucket/${BUCKET}/empty"
echo

if [[ "$DELETE_BUCKET" == true ]]; then
  echo "[storage-cleanup] Deleting bucket ${BUCKET} in confirmed non-production project ${PROJECT_REF}"
  curl --fail --silent --show-error \
    --request DELETE \
    --header "$AUTH_HEADER" \
    --header "$APIKEY_HEADER" \
    "${BASE_URL}/bucket/${BUCKET}"
  echo
fi
