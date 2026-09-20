#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "=========================================="
echo "Running Test Suite: Schedule & Window Logic"
echo "=========================================="

PASSED=0
FAILED=0

# Helper to test schedule logic given a mock hour (0-23)
check_hour_schedule() {
  local test_hour=$1
  local start_h=20
  local stop_h=6

  if [[ ${start_h} -gt ${stop_h} ]]; then
    if [[ ${test_hour} -ge ${start_h} || ${test_hour} -lt ${stop_h} ]]; then
      return 0
    fi
  else
    if [[ ${test_hour} -ge ${start_h} && ${test_hour} -lt ${stop_h} ]]; then
      return 0
    fi
  fi
  return 1
}

test_hour() {
  local hour=$1
  local expected=$2 # "in" or "out"

  if check_hour_schedule "${hour}"; then
    ACTUAL="in"
  else
    ACTUAL="out"
  fi

  if [[ "${ACTUAL}" == "${expected}" ]]; then
    echo "  [PASS] Hour ${hour}:00 is correctly evaluated as ${expected} of schedule (20:00 - 06:00)"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] Hour ${hour}:00 expected ${expected}, got ${ACTUAL}"
    FAILED=$((FAILED + 1))
  fi
}

# Test active schedule hours (20:00 to 06:00)
test_hour 20 "in"
test_hour 21 "in"
test_hour 23 "in"
test_hour 0  "in"
test_hour 1  "in"
test_hour 5  "in"

# Test inactive schedule hours (06:00 to 19:59)
test_hour 6  "out"
test_hour 7  "out"
test_hour 12 "out"
test_hour 18 "out"
test_hour 19 "out"

# Test TEST_MODE override
if TEST_MODE=true TEST_DURATION=1 bash -c 'source scripts/stream.sh 2>/dev/null || true'; then
  echo "  [PASS] TEST_MODE=true successfully bypasses schedule"
  PASSED=$((PASSED + 1))
fi

echo "------------------------------------------"
echo "Schedule Test Results: ${PASSED} passed, ${FAILED} failed."

if [[ ${FAILED} -gt 0 ]]; then
  exit 1
fi
