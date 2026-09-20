#!/usr/bin/env bash
set -euo pipefail

# Script to generate synthetic rain ambience video clips for development and testing

OUT_DIR="${1:-videos}"
DURATION="${2:-10}"

mkdir -p "${OUT_DIR}"

echo "Generating synthetic rain test videos in '${OUT_DIR}' (duration: ${DURATION}s each)..."

if ! command -v ffmpeg &>/dev/null; then
  echo "Error: 'ffmpeg' is required to generate test videos." >&2
  exit 1
fi

CLIPS=("rain-window" "rain-forest" "rain-rooftop" "rain-night")
COLORS=("darkblue" "forestgreen" "navy" "midnightblue")

for i in "${!CLIPS[@]}"; do
  CLIP_NAME="${CLIPS[$i]}"
  BG_COLOR="${COLORS[$i]}"
  OUT_FILE="${OUT_DIR}/${CLIP_NAME}.mp4"

  echo "Generating ${OUT_FILE}..."

  # Generate synthetic video (dark animated texture with text overlay) and synthetic audio (brown/pink noise for rain sound)
  ffmpeg -y \
    -f lavfi -i "color=c=${BG_COLOR}:s=1920x1080:r=30:d=${DURATION}" \
    -f lavfi -i "anoise=c=brown:r=48000:a=0.1" \
    -vf "drawtext=text='${CLIP_NAME} (Test Clip)':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 60 -keyint_min 60 -sc_threshold 0 \
    -c:a aac -b:a 128k -ar 48000 -ac 2 -t "${DURATION}" \
    "${OUT_FILE}"
done

echo "Successfully generated sample test videos:"
ls -lh "${OUT_DIR}"/*.mp4
