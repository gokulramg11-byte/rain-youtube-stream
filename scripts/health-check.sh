#!/usr/bin/env bash
set -euo pipefail

# Health Check Script for YouTube Rain Ambience Streaming System

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

# Load env defaults
if [[ -f ".env" ]]; then set -o allexport; source .env; set +o allexport; fi
if [[ -f "stream.env" ]]; then set -o allexport; source stream.env; set +o allexport; fi
if [[ -f "config/stream.env" ]]; then set -o allexport; source config/stream.env; set +o allexport; fi

TIMEZONE="${TIMEZONE:-Asia/Kolkata}"
START_TIME="${START_TIME:-20:00}"
STOP_TIME="${STOP_TIME:-06:00}"
TEST_MODE="${TEST_MODE:-false}"

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/stream.pid"
HEALTH_LOG="${LOG_DIR}/health.log"

log_health() {
  local timestamp
  timestamp="$(TZ="${TIMEZONE}" date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
  echo "[${timestamp}] $1" | tee -a "${HEALTH_LOG}"
}

is_in_schedule() {
  if [[ "${TEST_MODE}" == "true" ]]; then return 0; fi
  local current_hour
  current_hour=$(TZ="${TIMEZONE}" date +%H 2>/dev/null || date +%H)
  current_hour=$((10#$current_hour))
  local start_h=${START_TIME%%:*}
  local stop_h=${STOP_TIME%%:*}
  start_h=$((10#$start_h))
  stop_h=$((10#$stop_h))

  if [[ ${start_h} -gt ${stop_h} ]]; then
    if [[ ${current_hour} -ge ${start_h} || ${current_hour} -lt ${stop_h} ]]; then return 0; fi
  else
    if [[ ${current_hour} -ge ${start_h} && ${current_hour} -lt ${stop_h} ]]; then return 0; fi
  fi
  return 1
}

UNHEALTHY_REASONS=()

# 1. Schedule check
IN_SCHEDULE=false
if is_in_schedule; then
  IN_SCHEDULE=true
fi

# 2. Process check
SUPERVISOR_RUNNING=false
if [[ -f "${PID_FILE}" ]]; then
  SUPERVISOR_PID=$(cat "${PID_FILE}" 2>/dev/null || echo "")
  if [[ -n "${SUPERVISOR_PID}" ]] && kill -0 "${SUPERVISOR_PID}" 2>/dev/null; then
    SUPERVISOR_RUNNING=true
  fi
fi

if [[ "${IN_SCHEDULE}" == "true" && "${SUPERVISOR_RUNNING}" == "false" ]]; then
  UNHEALTHY_REASONS+=("Supervisor process is NOT running during scheduled streaming window")
fi

# 3. FFmpeg process check
if [[ "${SUPERVISOR_RUNNING}" == "true" ]]; then
  if ! pgrep ffmpeg &>/dev/null; then
    UNHEALTHY_REASONS+=("FFmpeg worker process is NOT active while supervisor is running")
  fi
fi

# 4. Network check
if command -v curl &>/dev/null; then
  if ! curl -s --head --request GET "https://www.youtube.com" --connect-timeout 5 >/dev/null; then
    UNHEALTHY_REASONS+=("Network connectivity to YouTube endpoint failed")
  fi
fi

# 5. Disk space check
if command -v df &>/dev/null; then
  AVAIL_KB=$(df -k . | tail -1 | awk '{print $4}')
  if [[ -n "${AVAIL_KB}" && ${AVAIL_KB} -lt 102400 ]]; then # less than 100MB
    UNHEALTHY_REASONS+=("Low disk space: < 100MB available")
  fi
fi

# Summary report
if [[ ${#UNHEALTHY_REASONS[@]} -eq 0 ]]; then
  if [[ "${SUPERVISOR_RUNNING}" == "true" ]]; then
    log_health "HEALTHY: Supervisor and FFmpeg streaming active. Network and system resources OK."
  else
    log_health "HEALTHY: System idle outside scheduled streaming window."
  fi
  echo "System Health: OK"
  exit 0
else
  log_health "UNHEALTHY: Issues detected: ${UNHEALTHY_REASONS[*]}"
  echo "System Health: UNHEALTHY"
  for REASON in "${UNHEALTHY_REASONS[@]}"; do
    echo "  - ${REASON}"
  done
  exit 1
fi
