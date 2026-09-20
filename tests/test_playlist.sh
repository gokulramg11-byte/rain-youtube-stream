#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

TEST_TMP_DIR="${PROJECT_ROOT}/tmp_test_playlist"
mkdir -p "${TEST_TMP_DIR}"

cleanup() {
  rm -rf "${TEST_TMP_DIR}"
}
trap cleanup EXIT

echo "=========================================="
echo "Running Test Suite: Playlist Parsing & Validation"
echo "=========================================="

PASSED=0
FAILED=0

assert_success() {
  local test_name="$1"
  shift
  if "$@"; then
    echo "  [PASS] ${test_name}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${test_name}"
    FAILED=$((FAILED + 1))
  fi
}

assert_failure() {
  local test_name="$1"
  shift
  if ! "$@" &>/dev/null; then
    echo "  [PASS] ${test_name}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${test_name} (expected failure but command succeeded)"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: Non-existent playlist file
assert_failure "Non-existent playlist file" bash scripts/validate-videos.sh "${TEST_TMP_DIR}/nonexistent.txt"

# Test 2: Empty playlist file
echo "# Only comments" > "${TEST_TMP_DIR}/empty_playlist.txt"
echo "" >> "${TEST_TMP_DIR}/empty_playlist.txt"
assert_failure "Empty playlist file" bash scripts/validate-videos.sh "${TEST_TMP_DIR}/empty_playlist.txt"

# Test 3: Playlist with missing video
echo "nonexistent_video.mp4" > "${TEST_TMP_DIR}/missing_video_playlist.txt"
assert_failure "Missing video in playlist" bash scripts/validate-videos.sh "${TEST_TMP_DIR}/missing_video_playlist.txt"

# Test 4: Valid playlist with mock video file
MOCK_VIDEO="${TEST_TMP_DIR}/sample.mp4"
if command -v ffmpeg &>/dev/null; then
  ffmpeg -y -f lavfi -i color=c=blue:s=320x240:d=1 -c:v libx264 -pix_fmt yuv420p "${MOCK_VIDEO}" &>/dev/null
else
  touch "${MOCK_VIDEO}"
fi
echo "${MOCK_VIDEO}" > "${TEST_TMP_DIR}/valid_playlist.txt"
assert_success "Valid playlist file check" bash scripts/validate-videos.sh "${TEST_TMP_DIR}/valid_playlist.txt"

echo "------------------------------------------"
echo "Playlist Test Results: ${PASSED} passed, ${FAILED} failed."

if [[ ${FAILED} -gt 0 ]]; then
  exit 1
fi
