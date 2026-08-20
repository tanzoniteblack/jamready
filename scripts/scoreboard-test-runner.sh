#!/bin/bash
# Shared support for local CRG scoreboard test runners. This file is sourced by
# test-remote-engine-scoreboards.sh and test-all-scoreboards.sh.

SCOREBOARD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOREBOARD_ALLURE_CONFIG="$SCOREBOARD_SCRIPT_DIR/../allurerc.mjs"

SCOREBOARD_ALL_VERSIONS=(
  v2025.9
  v2025.8
  v2025.7
  v2025.6
  v2025.5
  v2025.4
  v2025.3
  v2025.2
  v2025.1
  v2025.0
  # Seattle Derby Brats' temporary server-authoritative penalty-box fork.
  feature-pbt
)

scoreboard_require_positive_integer() {
  local option="$1" value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: $option must be a positive integer" >&2
    return 1
  fi
}

scoreboard_require_valid_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo "error: --port must be a valid TCP port" >&2
    return 1
  fi
}

scoreboard_require_port_finder() {
  if ! command -v lsof &>/dev/null; then
    echo "error: lsof is required to find an available Docker host port" >&2
    return 1
  fi
}

# Docker publishes to 0.0.0.0, so check every listening address rather than a
# particular host interface.
scoreboard_port_is_available() {
  ! lsof -nP -iTCP:"$1" -sTCP:LISTEN &>/dev/null
}

# Search one worker's port stride, ensuring parallel workers cannot choose the
# same fallback port.
scoreboard_find_available_port() {
  local candidate="$1" stride="$2"

  while (( candidate <= 65535 )); do
    if scoreboard_port_is_available "$candidate"; then
      echo "$candidate"
      return
    fi
    candidate=$((candidate + stride))
  done

  echo "error: no available port found at or above $1" >&2
  return 1
}

scoreboard_generate_allure_report() {
  local output_dir="$1"
  shift
  local input
  local inputs=()

  for input in "$@"; do
    [[ -d "$input" ]] && inputs+=("$input")
  done

  if [ ${#inputs[@]} -eq 0 ]; then
    echo "error: no Allure result directories were produced" >&2
    return 1
  fi

  if ! command -v npx &>/dev/null; then
    echo "error: npx is required to generate the Allure HTML report" >&2
    return 1
  fi

  if ! npx -y allure@3 generate "${inputs[@]}" \
    --config "$SCOREBOARD_ALLURE_CONFIG" \
    -o "$output_dir"; then
    echo "error: Allure report generation failed" >&2
    return 1
  fi
}
