#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"$ROOT_DIR/supabase/scripts/assert_local_only.sh"
"$ROOT_DIR/supabase/scripts/verify_local.sh"

command -v adb >/dev/null 2>&1 || {
  echo "[android-local] Android platform tools are required." >&2
  exit 1
}

devices="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
device_count="$(printf '%s\n' "$devices" | awk 'NF { count += 1 } END { print count + 0 }')"

if [[ "$device_count" -ne 1 ]]; then
  echo "[android-local] Expected exactly one ready Android emulator; found $device_count." >&2
  exit 1
fi

device="$(printf '%s\n' "$devices" | awk 'NF { print; exit }')"
if [[ "$device" != emulator-* ]]; then
  echo "[android-local] Refusing to configure a physical device: $device" >&2
  exit 1
fi

adb -s "$device" reverse tcp:54321 tcp:54321

echo "[android-local] Forwarded emulator localhost:54321 to the guarded local Supabase API."
