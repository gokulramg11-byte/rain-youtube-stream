#!/usr/bin/env bash
set -euo pipefail

# Script to validate videos referenced in playlist.txt

PLAYLIST_FILE="${1:-${PLAYLIST_FILE:-config/playlist.txt}}"
VIDEO_DIR="${VIDEO_DIR:-videos}"

echo "=========================================="
echo "Playlist Validation: ${PLAYLIST_FILE}"
echo "=========================================="

if [[ ! -f "${PLAYLIST_FILE}" ]]; then
  echo "Error: Playlist file '${PLAYLIST_FILE}' does not exist." >&2
  exit 1
fi

# Read non-comment, non-empty lines into array
mapfile -t PLAYLIST_ITEMS < <(grep -v '^[[:space:]]*#' "${PLAYLIST_FILE}" | grep -v '^[[:space:]]*$' || true)

if [[ ${#PLAYLIST_ITEMS[@]} -eq 0 ]]; then
  echo "Error: Playlist file '${PLAYLIST_FILE}' is empty or contains only comments." >&2
  exit 1
fi

VALID_COUNT=0
INVALID_COUNT=0
TOTAL_DURATION_SEC=0
FFPROBE_AVAIL=0

if command -v ffprobe &>/dev/null; then
  FFPROBE_AVAIL=1
else
  echo "Notice: 'ffprobe' not found. Performing basic file checks only."
fi

for ITEM in "${PLAYLIST_ITEMS[@]}"; do
  # Trim whitespace
  FILE_PATH=$(echo "${ITEM}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # Resolve path if relative
  RESOLVED_PATH="${FILE_PATH}"
  if [[ ! -f "${RESOLVED_PATH}" && -f "${VIDEO_DIR}/${FILE_PATH}" ]]; then
    RESOLVED_PATH="${VIDEO_DIR}/${FILE_PATH}"
  fi

  if [[ ! -f "${RESOLVED_PATH}" ]]; then
    echo "  ✗ ${FILE_PATH} — missing file"
    INVALID_COUNT=$((INVALID_COUNT + 1))
    continue
  fi

  if [[ ! -r "${RESOLVED_PATH}" ]]; then
    echo "  ✗ ${FILE_PATH} — file unreadable"
    INVALID_COUNT=$((INVALID_COUNT + 1))
    continue
  fi

  if [[ ${FFPROBE_AVAIL} -eq 1 ]]; then
    # Inspect video stream
    HAS_VIDEO=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "${RESOLVED_PATH}" || echo "")
    HAS_AUDIO=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "${RESOLVED_PATH}" || echo "")
    WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "${RESOLVED_PATH}" || echo "0")
    HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "${RESOLVED_PATH}" || echo "0")
    DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${RESOLVED_PATH}" || echo "0")

    if [[ -z "${HAS_VIDEO}" ]]; then
      echo "  ✗ ${FILE_PATH} — invalid MP4 (no video stream found)"
      INVALID_COUNT=$((INVALID_COUNT + 1))
      continue
    fi

    AUDIO_INFO="aac"
    if [[ -z "${HAS_AUDIO}" ]]; then
      AUDIO_INFO="no-audio (will be normalized with silent track)"
    fi

    DURATION_INT=${DURATION%.*}
    DURATION_INT=${DURATION_INT:-0}
    TOTAL_DURATION_SEC=$((TOTAL_DURATION_SEC + DURATION_INT))

    echo "  ✓ ${FILE_PATH} (${WIDTH}x${HEIGHT}, video:${HAS_VIDEO}, audio:${AUDIO_INFO}, duration:${DURATION_INT}s)"
    VALID_COUNT=$((VALID_COUNT + 1))
  else
    echo "  ✓ ${FILE_PATH} (file exists and readable)"
    VALID_COUNT=$((VALID_COUNT + 1))
  fi
done

echo "------------------------------------------"
TOTAL_MINS=$((TOTAL_DURATION_SEC / 60))
REMAINING_SECS=$((TOTAL_DURATION_SEC % 60))

if [[ ${FFPROBE_AVAIL} -eq 1 ]]; then
  echo "Playlist duration: ${TOTAL_MINS}m ${REMAINING_SECS}s (${TOTAL_DURATION_SEC} total seconds)"
fi

echo "Summary: ${VALID_COUNT} valid, ${INVALID_COUNT} invalid."

if [[ ${INVALID_COUNT} -gt 0 ]]; then
  echo "Playlist validation FAILED." >&2
  exit 1
else
  echo "Playlist validation PASSED."
  exit 0
fi
