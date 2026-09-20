#!/usr/bin/env bash
set -euo pipefail

# Command script to display formatted status of YouTube Rain Ambience stream

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# Load env defaults
if [[ -f ".env" ]]; then set -o allexport; source .env; set +o allexport; fi
if [[ -f "stream.env" ]]; then set -o allexport; source stream.env; set +o allexport; fi
if [[ -f "config/stream.env" ]]; then set -o allexport; source config/stream.env; set +o allexport; fi

TIMEZONE="${TIMEZONE:-Asia/Kolkata}"
START_TIME="${START_TIME:-20:00}"
STOP_TIME="${STOP_TIME:-06:00}"
STREAM_PROFILE="${STREAM_PROFILE:-1080p}"
PLAYLIST_FILE="${PLAYLIST_FILE:-config/playlist.txt}"
PLAYLIST_MODE="${PLAYLIST_MODE:-sequential}"

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/stream.pid"
STATE_FILE="${LOG_DIR}/stream.state"

STATUS="STOPPED"
SUPERVISOR_PID="N/A"
FFMPEG_PID="N/A"
UPTIME="00:00:00"

if [[ -f "${STATE_FILE}" ]]; then
  STATUS=$(cat "${STATE_FILE}" 2>/dev/null || echo "STOPPED")
fi

if [[ -f "${PID_FILE}" ]]; then
  PID_VAL=$(cat "${PID_FILE}" 2>/dev/null || echo "")
  if [[ -n "${PID_VAL}" ]] && kill -0 "${PID_VAL}" 2>/dev/null; then
    SUPERVISOR_PID="${PID_VAL}"
    STATUS="RUNNING"

    # Find FFmpeg child process if running
    CHILD_FFMPEG="N/A"
    if command -v pgrep &>/dev/null; then
      CHILD_FFMPEG=$(pgrep -P "${SUPERVISOR_PID}" ffmpeg 2>/dev/null || pgrep ffmpeg 2>/dev/null || echo "N/A")
    else
      CHILD_FFMPEG=$(ps -ef 2>/dev/null | grep ffmpeg | grep -v grep | awk '{print $2}' | head -n 1 || echo "N/A")
    fi
    FFMPEG_PID="${CHILD_FFMPEG}"

    # Calculate Uptime
    PID_START_SEC=$(ps -o lstart= -p "${SUPERVISOR_PID}" 2>/dev/null | xargs -I{} date -d "{}" +%s 2>/dev/null || echo "")
    if [[ -n "${PID_START_SEC}" ]]; then
      NOW=$(date +%s)
      DIFF=$((NOW - PID_START_SEC))
      HOURS=$((DIFF / 3600))
      MINS=$(((DIFF % 3600) / 60))
      SECS=$((DIFF % 60))
      UPTIME=$(printf "%02d:%02d:%02d" ${HOURS} ${MINS} ${SECS})
    fi
  else
    STATUS="STOPPED"
  fi
fi

# Count playlist items
VIDEO_COUNT=0
if [[ -f "${PLAYLIST_FILE}" ]]; then
  VIDEO_COUNT=$(grep -v '^[[:space:]]*#' "${PLAYLIST_FILE}" | grep -c -v '^[[:space:]]*$' || echo "0")
fi

# Format profile string
PROFILE_STR="1080p30"
if [[ "${STREAM_PROFILE}" == "720p" ]]; then
  PROFILE_STR="720p30"
fi

echo "=========================================="
echo "Rain Stream Status"
echo "=========================================="
printf "%-18s %s\n" "Schedule:" "${START_TIME}–${STOP_TIME} ${TIMEZONE}"
printf "%-18s %s\n" "Status:" "${STATUS}"
printf "%-18s %s\n" "Supervisor PID:" "${SUPERVISOR_PID}"
printf "%-18s %s\n" "FFmpeg PID:" "${FFMPEG_PID}"
printf "%-18s %d videos\n" "Playlist:" "${VIDEO_COUNT}"
printf "%-18s %s\n" "Mode:" "${PLAYLIST_MODE}"
printf "%-18s %s\n" "Current profile:" "${PROFILE_STR}"
printf "%-18s %s\n" "Uptime:" "${UPTIME}"
echo "=========================================="
