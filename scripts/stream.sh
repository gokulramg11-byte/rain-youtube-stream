#!/usr/bin/env bash
set -euo pipefail

# Main Streaming Supervisor Script for YouTube Rain Ambience

# -----------------------------------------------------------------------------
# Configuration & Defaults
# -----------------------------------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# Preserve caller's environment overrides
PRE_TEST_MODE="${TEST_MODE:-}"
PRE_DRY_RUN="${DRY_RUN:-}"

# Load environment variables if config files exist
if [[ -f ".env" ]]; then
  set -o allexport; source .env; set +o allexport
elif [[ -f "stream.env" ]]; then
  set -o allexport; source stream.env; set +o allexport
elif [[ -f "config/stream.env" ]]; then
  set -o allexport; source config/stream.env; set +o allexport
fi

if [[ -n "${PRE_TEST_MODE}" ]]; then TEST_MODE="${PRE_TEST_MODE}"; fi
if [[ -n "${PRE_DRY_RUN}" ]]; then DRY_RUN="${PRE_DRY_RUN}"; fi

YOUTUBE_STREAM_URL="${YOUTUBE_STREAM_URL:-rtmps://a.rtmp.youtube.com/live2}"
YOUTUBE_STREAM_KEY="${YOUTUBE_STREAM_KEY:-}"
STREAM_PROFILE="${STREAM_PROFILE:-1080p}"

if [[ "${STREAM_PROFILE}" == "720p" ]]; then
  VIDEO_WIDTH="${VIDEO_WIDTH:-1280}"
  VIDEO_HEIGHT="${VIDEO_HEIGHT:-720}"
  VIDEO_BITRATE="${VIDEO_BITRATE:-4M}"
else
  VIDEO_WIDTH="${VIDEO_WIDTH:-1920}"
  VIDEO_HEIGHT="${VIDEO_HEIGHT:-1080}"
  VIDEO_BITRATE="${VIDEO_BITRATE:-10M}"
fi

VIDEO_FPS="${VIDEO_FPS:-30}"
AUDIO_BITRATE="${AUDIO_BITRATE:-128k}"
KEYFRAME_INTERVAL="${KEYFRAME_INTERVAL:-2}"
PLAYLIST_FILE="${PLAYLIST_FILE:-config/playlist.txt}"
VIDEO_DIR="${VIDEO_DIR:-videos}"
PLAYLIST_MODE="${PLAYLIST_MODE:-sequential}"

TIMEZONE="${TIMEZONE:-Asia/Kolkata}"
START_TIME="${START_TIME:-20:00}"
STOP_TIME="${STOP_TIME:-06:00}"

MAX_RECONNECT_ATTEMPTS="${MAX_RECONNECT_ATTEMPTS:-10}"
RECONNECT_DELAY_SEC="${RECONNECT_DELAY_SEC:-5}"
MAX_RECONNECT_DELAY_SEC="${MAX_RECONNECT_DELAY_SEC:-60}"

TEST_MODE="${TEST_MODE:-false}"
TEST_DURATION="${TEST_DURATION:-300}"
DRY_RUN="${DRY_RUN:-false}"

LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/stream.log"
PID_FILE="${LOG_DIR}/stream.pid"
STATE_FILE="${LOG_DIR}/stream.state"
CONCAT_FILE="${PROJECT_ROOT}/concat_list.txt"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
sanitize_text() {
  local input="$1"
  if [[ -n "${YOUTUBE_STREAM_KEY}" ]]; then
    echo "${input}" | sed "s|${YOUTUBE_STREAM_KEY}|[REDACTED]|g"
  else
    echo "${input}"
  fi
}

log_message() {
  local level="$1"
  shift
  local msg="$*"
  local timestamp
  timestamp="$(TZ="${TIMEZONE}" date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
  local sanitized
  sanitized="$(sanitize_text "${msg}")"
  echo "[${timestamp}] [${level}] ${sanitized}" | tee -a "${LOG_FILE}"
}

set_state() {
  local new_state="$1"
  echo "${new_state}" > "${STATE_FILE}"
}

DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

send_notification() {
  local title="$1"
  local message="$2"

  if [[ -n "${DISCORD_WEBHOOK_URL}" ]] && command -v curl &>/dev/null; then
    local payload
    payload=$(cat <<EOF
{
  "embeds": [{
    "title": "${title}",
    "description": "${message}",
    "color": 3066993
  }]
}
EOF
)
    curl -s -H "Content-Type: application/json" -X POST -d "${payload}" "${DISCORD_WEBHOOK_URL}" &>/dev/null || true
  fi

  if [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]] && command -v curl &>/dev/null; then
    local text="*${title}*%0A${message}"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${text}" \
      -d "parse_mode=Markdown" &>/dev/null || true
  fi
}

# Check if current time is within streaming window (20:00 to 06:00 IST)
is_in_schedule() {
  if [[ "${TEST_MODE}" == "true" ]]; then
    return 0
  fi

  local current_hour
  current_hour=$(TZ="${TIMEZONE}" date +%H 2>/dev/null || date +%H)
  current_hour=$((10#$current_hour))

  local start_h=${START_TIME%%:*}
  local stop_h=${STOP_TIME%%:*}
  start_h=$((10#$start_h))
  stop_h=$((10#$stop_h))

  # Schedule 20:00 to 06:00 crosses midnight
  if [[ ${start_h} -gt ${stop_h} ]]; then
    if [[ ${current_hour} -ge ${start_h} || ${current_hour} -lt ${stop_h} ]]; then
      return 0
    fi
  else
    if [[ ${current_hour} -ge ${start_h} && ${current_hour} -lt ${stop_h} ]]; then
      return 0
    fi
  fi
  return 1
}

build_concat_file() {
  log_message "INFO" "Reading playlist file: ${PLAYLIST_FILE}"
  if [[ ! -f "${PLAYLIST_FILE}" ]]; then
    log_message "ERROR" "Playlist file '${PLAYLIST_FILE}' not found."
    return 1
  fi

  mapfile -t RAW_ITEMS < <(grep -v '^[[:space:]]*#' "${PLAYLIST_FILE}" | grep -v '^[[:space:]]*$' || true)

  if [[ ${#RAW_ITEMS[@]} -eq 0 ]]; then
    log_message "ERROR" "Playlist file is empty or invalid."
    return 1
  fi

  local VALID_FILES=()
  for ITEM in "${RAW_ITEMS[@]}"; do
    local FILE_PATH
    FILE_PATH=$(echo "${ITEM}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    local RESOLVED="${FILE_PATH}"
    if [[ ! -f "${RESOLVED}" && -f "${VIDEO_DIR}/${FILE_PATH}" ]]; then
      RESOLVED="${VIDEO_DIR}/${FILE_PATH}"
    fi

    if [[ -f "${RESOLVED}" ]]; then
      # Convert to absolute path
      local ABS_PATH
      ABS_PATH="$(cd "$(dirname "${RESOLVED}")" && pwd)/$(basename "${RESOLVED}")"
      VALID_FILES+=("${ABS_PATH}")
    else
      log_message "WARN" "Skipping missing playlist video file: ${FILE_PATH}"
    fi
  done

  if [[ ${#VALID_FILES[@]} -eq 0 ]]; then
    log_message "ERROR" "No valid video files found in playlist."
    return 1
  fi

  # Apply PLAYLIST_MODE
  if [[ "${PLAYLIST_MODE}" == "random" && ${#VALID_FILES[@]} -gt 1 ]]; then
    log_message "INFO" "Shuffling playlist in random mode..."
    # Shuffle using awk/RANDOM
    mapfile -t VALID_FILES < <(printf '%s\n' "${VALID_FILES[@]}" | awk 'BEGIN{srand()}{print rand()"\t"$0}' | sort -n | cut -f2-)
  fi

  # Generate FFmpeg concat demuxer file
  > "${CONCAT_FILE}"
  for ABS_FILE in "${VALID_FILES[@]}"; do
    # Convert MSYS/Git Bash POSIX path /c/path to C:/path for native Windows FFmpeg
    if [[ "${ABS_FILE}" =~ ^/([a-zA-Z])/(.*) ]]; then
      local DRIVE="${BASH_REMATCH[1]}"
      local REST="${BASH_REMATCH[2]}"
      local UPPER_DRIVE
      UPPER_DRIVE=$(echo "${DRIVE}" | tr '[:lower:]' '[:upper:]')
      ABS_FILE="${UPPER_DRIVE}:/${REST}"
    fi

    # Escape single quotes for ffmpeg concat demuxer
    local ESCAPED_PATH
    ESCAPED_PATH=$(echo "${ABS_FILE}" | sed "s/'/'\\\\''/g")
    echo "file '${ESCAPED_PATH}'" >> "${CONCAT_FILE}"
  done

  log_message "INFO" "Generated FFmpeg concat list (${#VALID_FILES[@]} videos) -> ${CONCAT_FILE}"
  return 0
}

# -----------------------------------------------------------------------------
# Supervisor Lifecycle & Traps
# -----------------------------------------------------------------------------
echo $$ > "${PID_FILE}"
set_state "STARTING"

FFMPEG_PID=""

cleanup() {
  log_message "INFO" "Received shutdown signal. Stopping supervisor..."
  set_state "STOPPING"
  if [[ -n "${FFMPEG_PID}" ]] && kill -0 "${FFMPEG_PID}" 2>/dev/null; then
    log_message "INFO" "Terminating FFmpeg process (PID ${FFMPEG_PID})..."
    kill -TERM "${FFMPEG_PID}" 2>/dev/null || true
    sleep 2
    if kill -0 "${FFMPEG_PID}" 2>/dev/null; then
      kill -KILL "${FFMPEG_PID}" 2>/dev/null || true
    fi
  fi
  rm -f "${PID_FILE}" "${CONCAT_FILE}" 2>/dev/null || true
  set_state "STOPPED"
  send_notification "🛑 YouTube Live Stream STOPPED" "Supervisor process shut down cleanly."
  log_message "INFO" "Supervisor stopped cleanly."
  exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# -----------------------------------------------------------------------------
# Startup Validation
# -----------------------------------------------------------------------------
log_message "INFO" "=== Starting YouTube Rain Ambience Supervisor ==="
log_message "INFO" "Profile: ${STREAM_PROFILE} (${VIDEO_WIDTH}x${VIDEO_HEIGHT}@${VIDEO_FPS}fps, ${VIDEO_BITRATE})"
log_message "INFO" "Schedule Window: ${START_TIME} to ${STOP_TIME} (${TIMEZONE})"
log_message "INFO" "Test Mode: ${TEST_MODE}, Dry Run: ${DRY_RUN}"

if [[ "${DRY_RUN}" != "true" && -z "${YOUTUBE_STREAM_KEY}" ]]; then
  log_message "ERROR" "YOUTUBE_STREAM_KEY is not set! Aborting startup."
  set_state "FAILED"
  exit 1
fi

if ! is_in_schedule; then
  log_message "ERROR" "Current time is outside the scheduled streaming window (${START_TIME} - ${STOP_TIME} ${TIMEZONE})."
  log_message "ERROR" "Use TEST_MODE=true to bypass schedule checks for development."
  set_state "STOPPED"
  exit 1
fi

if ! build_concat_file; then
  log_message "ERROR" "Failed to build playlist concat file."
  set_state "FAILED"
  exit 1
fi

# -----------------------------------------------------------------------------
# Main Supervisor Loop
# -----------------------------------------------------------------------------
set_state "RUNNING"
send_notification "🌧️ YouTube Live Stream STARTED" "Profile: ${STREAM_PROFILE} (${VIDEO_WIDTH}x${VIDEO_HEIGHT}@${VIDEO_FPS}fps), Mode: ${PLAYLIST_MODE}"
GOP=$((VIDEO_FPS * KEYFRAME_INTERVAL))
DEST_TARGET="${YOUTUBE_STREAM_URL}/${YOUTUBE_STREAM_KEY}"

if [[ "${DRY_RUN}" == "true" ]]; then
  DEST_TARGET="-f null -"
fi

RETRY_COUNT=0
START_TIMESTAMP=$(date +%s)

while true; do
  # Check schedule before launching FFmpeg cycle
  if ! is_in_schedule; then
    log_message "INFO" "Scheduled stop time reached (${STOP_TIME} ${TIMEZONE}). Ending stream session."
    set_state "STOPPED"
    break
  fi

  # Check TEST_MODE duration limit
  if [[ "${TEST_MODE}" == "true" ]]; then
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIMESTAMP))
    if [[ ${ELAPSED} -ge ${TEST_DURATION} ]]; then
      log_message "INFO" "TEST_MODE duration threshold (${TEST_DURATION}s) reached. Stopping stream."
      set_state "STOPPED"
      break
    fi
  fi

  log_message "INFO" "Launching FFmpeg streaming pipeline..."

  FFMPEG_CMD=(
    ffmpeg -re
    -fflags +genpts+igndts
    -f concat -safe 0 -stream_loop -1 -i "${CONCAT_FILE}"
    -r "${VIDEO_FPS}"
    -c:v libx264 -preset veryfast -pix_fmt yuv420p
    -b:v "${VIDEO_BITRATE}" -maxrate "${VIDEO_BITRATE}" -bufsize 20M
    -g "${GOP}" -keyint_min "${GOP}" -sc_threshold 0
    -c:a aac -b:a "${AUDIO_BITRATE}" -ar 48000 -ac 2
    -flvflags no_duration_filesize
    -rw_timeout 15000000
    -f flv
  )

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_message "INFO" "DRY RUN MODE: FFmpeg command preview:"
    log_message "INFO" "${FFMPEG_CMD[*]} [REDACTED_TARGET]"
    "${FFMPEG_CMD[@]}" -f null - &>/dev/null &
    FFMPEG_PID=$!
  else
    log_message "INFO" "Executing FFmpeg live stream directly to target..."
    "${FFMPEG_CMD[@]}" "${DEST_TARGET}" &
    FFMPEG_PID=$!
  fi
  CYCLE_START=$(date +%s)

  # Monitor FFmpeg execution
  while kill -0 "${FFMPEG_PID}" 2>/dev/null; do
    sleep 5

    # Periodically check schedule during active stream
    if ! is_in_schedule; then
      log_message "INFO" "Scheduled stop time reached during active stream. Sending SIGTERM to FFmpeg..."
      kill -TERM "${FFMPEG_PID}" 2>/dev/null || true
      wait "${FFMPEG_PID}" 2>/dev/null || true
      set_state "STOPPED"
      break 2
    fi

    # Check TEST_MODE duration limit during active stream
    if [[ "${TEST_MODE}" == "true" ]]; then
      NOW=$(date +%s)
      ELAPSED=$((NOW - START_TIMESTAMP))
      if [[ ${ELAPSED} -ge ${TEST_DURATION} ]]; then
        log_message "INFO" "TEST_MODE duration limit reached during stream. Stopping FFmpeg..."
        kill -TERM "${FFMPEG_PID}" 2>/dev/null || true
        wait "${FFMPEG_PID}" 2>/dev/null || true
        set_state "STOPPED"
        break 2
      fi
    fi
  done

  wait "${FFMPEG_PID}" 2>/dev/null || true
  CYCLE_END=$(date +%s)
  CYCLE_DURATION=$((CYCLE_END - CYCLE_START))

  # If FFmpeg ran for more than 60s, reset retry counter
  if [[ ${CYCLE_DURATION} -gt 60 ]]; then
    RETRY_COUNT=0
  fi

  # Check if shutdown was requested or schedule ended
  if ! is_in_schedule || [[ "$(cat "${STATE_FILE}" 2>/dev/null)" == "STOPPING" ]]; then
    log_message "INFO" "Stream stopped per schedule or operator shutdown."
    break
  fi

  # FFmpeg crashed or disconnected unexpectedly
  RETRY_COUNT=$((RETRY_COUNT + 1))
  log_message "WARN" "FFmpeg process exited unexpectedly (cycle duration: ${CYCLE_DURATION}s). Attempt ${RETRY_COUNT}/${MAX_RECONNECT_ATTEMPTS}."

  if [[ ${RETRY_COUNT} -gt ${MAX_RECONNECT_ATTEMPTS} ]]; then
    log_message "ERROR" "Maximum reconnect attempts (${MAX_RECONNECT_ATTEMPTS}) reached. Supervisor terminating."
    set_state "FAILED"
    exit 1
  fi

  # Calculate exponential backoff delay
  BACKOFF_DELAY=$((RECONNECT_DELAY_SEC * (2 ** (RETRY_COUNT - 1))))
  if [[ ${BACKOFF_DELAY} -gt ${MAX_RECONNECT_DELAY_SEC} ]]; then
    BACKOFF_DELAY=${MAX_RECONNECT_DELAY_SEC}
  fi

  log_message "INFO" "Waiting ${BACKOFF_DELAY} seconds before attempting stream reconnect..."
  sleep "${BACKOFF_DELAY}"
done

set_state "STOPPED"
log_message "INFO" "Supervisor loop completed."
