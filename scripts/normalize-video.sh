#!/usr/bin/env bash
set -euo pipefail

# Script to normalize a raw MP4 video clip to target streaming specs (1080p30 / H.264 / AAC stereo 48kHz)

INPUT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "${INPUT_FILE}" ]]; then
  echo "Usage: $0 <input.mp4> [output.mp4]" >&2
  exit 1
fi

if [[ ! -f "${INPUT_FILE}" ]]; then
  echo "Error: Input file '${INPUT_FILE}' does not exist." >&2
  exit 1
fi

if [[ -z "${OUTPUT_FILE}" ]]; then
  FILENAME=$(basename "${INPUT_FILE}")
  DIRNAME=$(dirname "${INPUT_FILE}")
  OUTPUT_FILE="${DIRNAME}/normalized_${FILENAME}"
fi

WIDTH="${VIDEO_WIDTH:-1920}"
HEIGHT="${VIDEO_HEIGHT:-1080}"
FPS="${VIDEO_FPS:-30}"
KEYFRAME_INTERVAL="${KEYFRAME_INTERVAL:-2}"
GOP=$((FPS * KEYFRAME_INTERVAL))

echo "Normalizing '${INPUT_FILE}' -> '${OUTPUT_FILE}'..."
echo "Specs: ${WIDTH}x${HEIGHT} @ ${FPS}fps, H.264 (yuv420p), AAC 48kHz Stereo (GOP=${GOP})"

if ! command -v ffmpeg &>/dev/null; then
  echo "Error: 'ffmpeg' command is required for video normalization." >&2
  exit 1
fi

# Check if input has audio stream using ffprobe
HAS_AUDIO=0
if command -v ffprobe &>/dev/null; then
  AUDIO_CHECK=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "${INPUT_FILE}" || echo "")
  if [[ -n "${AUDIO_CHECK}" ]]; then
    HAS_AUDIO=1
  fi
fi

if [[ ${HAS_AUDIO} -eq 1 ]]; then
  echo "Audio stream detected. Normalizing video + audio streams..."
  ffmpeg -y -i "${INPUT_FILE}" \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,fps=${FPS}" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -g "${GOP}" -keyint_min "${GOP}" -sc_threshold 0 \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    "${OUTPUT_FILE}"
else
  echo "No audio stream detected. Generating synthetic silent stereo AAC track..."
  ffmpeg -y -i "${INPUT_FILE}" \
    -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,fps=${FPS}" \
    -c:v libx264 -preset veryfast -pix_fmt yuv420p -g "${GOP}" -keyint_min "${GOP}" -sc_threshold 0 \
    -c:a aac -b:a 128k -ar 48000 -ac 2 -shortest \
    "${OUTPUT_FILE}"
fi

echo "Successfully normalized video: ${OUTPUT_FILE}"
