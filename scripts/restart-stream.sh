#!/usr/bin/env bash
set -euo pipefail

# Command script to restart YouTube Live Stream

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "=========================================="
echo "Restarting YouTube Rain Ambience Stream..."
echo "=========================================="

bash scripts/stop-stream.sh

sleep 2

bash scripts/start-stream.sh "$@"
