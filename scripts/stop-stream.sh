#!/usr/bin/env bash
set -euo pipefail

# Command script to gracefully stop YouTube Live Stream

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/stream.pid"
STATE_FILE="${LOG_DIR}/stream.state"

echo "=========================================="
echo "Stopping YouTube Rain Ambience Stream..."
echo "=========================================="

STOPPED_ANY=false

if [[ -f "${PID_FILE}" ]]; then
  STREAM_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
  if [[ -n "${STREAM_PID}" ]] && kill -0 "${STREAM_PID}" 2>/dev/null; then
    echo "Sending graceful SIGTERM to stream supervisor (PID: ${STREAM_PID})..."
    kill -TERM "${STREAM_PID}" 2>/dev/null || true
    STOPPED_ANY=true

    # Wait up to 10 seconds for process termination
    WAIT_SEC=10
    while [[ ${WAIT_SEC} -gt 0 ]]; do
      if ! kill -0 "${STREAM_PID}" 2>/dev/null; then
        break
      fi
      sleep 1
      WAIT_SEC=$((WAIT_SEC - 1))
    done

    # Force kill if still alive
    if kill -0 "${STREAM_PID}" 2>/dev/null; then
      echo "Process did not terminate within timeout. Sending SIGKILL..."
      kill -KILL "${STREAM_PID}" 2>/dev/null || true
    fi
  fi
  rm -f "${PID_FILE}"
fi

# Fallback: kill any orphaned ffmpeg or stream.sh processes belonging to project
PIDS=""
if command -v pgrep &>/dev/null; then
  PIDS=$(pgrep -f "scripts/stream.sh" || true)
else
  PIDS=$(ps -ef 2>/dev/null | grep "scripts/stream.sh" | grep -v grep | awk '{print $2}' || true)
fi

if [[ -n "${PIDS}" ]]; then
  echo "Terminating remaining supervisor process(es): ${PIDS}"
  kill -TERM ${PIDS} 2>/dev/null || true
  STOPPED_ANY=true
fi

echo "STOPPED" > "${STATE_FILE}"

if [[ "${STOPPED_ANY}" == "true" ]]; then
  echo "✓ YouTube Live Stream has been cleanly stopped."
else
  echo "Notice: No active YouTube Live Stream was running."
fi

exit 0
