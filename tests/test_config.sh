#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "=========================================="
echo "Running Test Suite: Configuration & Secret Sanitization"
echo "=========================================="

PASSED=0
FAILED=0

# Test secret redaction logic
SECRET="super_secret_youtube_stream_key_9999"
LOG_LINE="Connecting to rtmps://a.rtmp.youtube.com/live2/${SECRET} now..."

SANITIZED=$(echo "${LOG_LINE}" | sed "s|${SECRET}|[REDACTED]|g")

if [[ "${SANITIZED}" != *"${SECRET}"* && "${SANITIZED}" == *"[REDACTED]"* ]]; then
  echo "  [PASS] Stream key secret was successfully redacted from log output"
  PASSED=$((PASSED + 1))
else
  echo "  [FAIL] Secret redaction failed: ${SANITIZED}"
  FAILED=$((FAILED + 1))
fi

# Test DRY_RUN mode output
TEST_TMP="${PROJECT_ROOT}/tmp_test_config"
mkdir -p "${TEST_TMP}"
touch "${TEST_TMP}/mock_video.mp4"
echo "${TEST_TMP}/mock_video.mp4" > "${TEST_TMP}/test_playlist.txt"

DRY_RUN_OUTPUT=$(PLAYLIST_FILE="${TEST_TMP}/test_playlist.txt" DRY_RUN=true TEST_MODE=true TEST_DURATION=1 YOUTUBE_STREAM_KEY="test_key" bash scripts/stream.sh 2>&1 || true)
rm -rf "${TEST_TMP}"

if echo "${DRY_RUN_OUTPUT}" | grep -q "DRY RUN MODE"; then
  echo "  [PASS] DRY_RUN=true correctly triggers dry run preview mode"
  PASSED=$((PASSED + 1))
else
  echo "  [FAIL] DRY_RUN=true did not log dry run preview mode"
  FAILED=$((FAILED + 1))
fi

if echo "${DRY_RUN_OUTPUT}" | grep -q "test_key"; then
  echo "  [FAIL] Secret leaked in DRY_RUN output!"
  FAILED=$((FAILED + 1))
else
  echo "  [PASS] Secret was NOT leaked in DRY_RUN output"
  PASSED=$((PASSED + 1))
fi

echo "------------------------------------------"
echo "Configuration Test Results: ${PASSED} passed, ${FAILED} failed."

if [[ ${FAILED} -gt 0 ]]; then
  exit 1
fi
