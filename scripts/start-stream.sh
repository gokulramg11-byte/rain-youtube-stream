#!/usr/bin/env bash
set -euo pipefail

# Command script to initiate YouTube Live Stream

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

FORCE_START=false

for arg in "$@"; do
  if [[ "${arg}" == "--force" ]]; then
    FORCE_START=true
  fi
done

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/stream.pid"
STATE_FILE="${LOG_DIR}/stream.state"

echo "=========================================="
echo "Starting YouTube Rain Ambience Stream..."
echo "=========================================="

# Check if stream is already running
if [[ -f "${PID_FILE}" ]]; then
  EXISTING_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
  if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" 2>/dev/null; then
    echo "Error: Stream is already running (PID: ${EXISTING_PID}). Use stop-stream.sh or restart-stream.sh first." >&2
    exit 1
  fi
fi

# Run playlist validation script
if [[ -f "scripts/validate-videos.sh" ]]; then
  echo "Validating playlist and video files..."
  if ! bash scripts/validate-videos.sh; then
    echo "Error: Playlist validation failed. Aborting stream startup." >&2
    exit 1
  fi
fi

if [[ "${FORCE_START}" == "true" ]]; then
  export TEST_MODE=true
  echo "Notice: Force flag detected. Setting TEST_MODE=true to bypass schedule checks."
fi

echo "Launching streaming supervisor daemon..."
nohup bash scripts/stream.sh >/dev/null 2>&1 &
NEW_PID=$!

sleep 2

if kill -0 "${NEW_PID}" 2>/dev/null; then
  echo "${NEW_PID}" > "${PID_FILE}"
  echo "✓ Stream started successfully (PID: ${NEW_PID})."
  echo "Logs available at: logs/stream.log"
  exit 0
else
  echo "Error: Stream supervisor failed to start. Check logs/stream.log for details." >&2
  exit 1
fi
