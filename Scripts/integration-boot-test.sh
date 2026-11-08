#!/usr/bin/env bash
# Boots a real Linux installer image with a signed nestctl and checks that the machine comes up and
# stays running. Not part of `make test`: it needs the virtualization entitlement and an image.
#
# Usage: Scripts/integration-boot-test.sh <arm64-installer.iso> [seconds]
set -euo pipefail
cd "$(dirname "$0")/.."

ISO="${1:?usage: $0 <arm64-installer.iso> [seconds]}"
SECONDS_TO_RUN="${2:-30}"
WORK="$(mktemp -d -t nestsuite-integration)"
export NESTSUITE_LIBRARY="$WORK/library"
trap 'kill -9 "${PID:-0}" 2>/dev/null || true; rm -r "$WORK"' EXIT

make nestctl >/dev/null
build/nestctl create integration --cpus 2 --memory 1GiB --disk 8GiB >/dev/null

build/nestctl run integration --iso "$ISO" >"$WORK/run.log" 2>&1 &
PID=$!
sleep "$SECONDS_TO_RUN"

fail() { echo "✘ $1"; echo "--- nestctl output"; cat "$WORK/run.log"; exit 1; }
kill -0 "$PID" 2>/dev/null || fail "the machine stopped before $SECONDS_TO_RUN s"
for file in Disk.img NVRAM MachineIdentifier MACAddress; do
  [[ -f "$NESTSUITE_LIBRARY/integration.nestvm/$file" ]] || fail "$file was not created"
done
build/nestctl run integration >/dev/null 2>&1 && fail "a second run of the same machine was not refused"

kill -INT "$PID"; sleep 2; kill -INT "$PID" 2>/dev/null || true
wait "$PID" || true
grep -q "stopped" "$WORK/run.log" || fail "the machine did not report a clean stop"
echo "✔ booted, stayed running for $SECONDS_TO_RUN s, refused a second start, stopped cleanly"
