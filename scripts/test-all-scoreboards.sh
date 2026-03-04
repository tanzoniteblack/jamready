#!/bin/bash
# Run integration tests against each scoreboard Docker image.
# Run build-scoreboard-images.sh first.
#
# Usage: ./scripts/test-all-scoreboards.sh [--versions v2025.3,v2025.9] [-- flutter test args]
#
# Options:
#   --versions  Comma-separated list of versions to test (default: all)
#   --host      Override the host address passed to the tests (auto-detected by default)
#   --port      Host port to map the scoreboard to (default: 8001)
#
# Auto-detection:
#   Android emulator  → Docker binds 0.0.0.0, tests use 10.0.2.2
#   iOS simulator     → Docker binds 127.0.0.1, tests use 127.0.0.1
#
# Passes any args after -- directly to flutter test.

set -euo pipefail

ALL_VERSIONS=(
  v2023.7
  v2025.0
  v2025.1
  v2025.2
  v2025.3
  v2025.4
  v2025.5
  v2025.6
  v2025.7
  v2025.8
  v2025.9
)

VERSIONS=()
HOST=""
DOCKER_BIND=""
HOST_OVERRIDE=""
PORT=8001
FLUTTER_ARGS=()

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions)
      IFS=',' read -ra VERSIONS <<< "$2"
      shift 2
      ;;
    --host)
      HOST_OVERRIDE="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --)
      shift
      FLUTTER_ARGS=("$@")
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Detect the test device and set HOST (address the device uses to reach the host)
# and DOCKER_BIND (address Docker listens on).
detect_host() {
  if [[ -n "$HOST_OVERRIDE" ]]; then
    HOST="$HOST_OVERRIDE"
    DOCKER_BIND="0.0.0.0"
    echo "--> Host overridden to $HOST"
    return
  fi

  local DEVICES
  DEVICES=$(flutter devices 2>/dev/null || true)

  if echo "$DEVICES" | grep -qi "android"; then
    # Android emulator reaches the host machine via 10.0.2.2
    HOST="10.0.2.2"
    DOCKER_BIND="0.0.0.0"
    echo "--> Detected Android device — using host $HOST (Docker bind: $DOCKER_BIND)"
  elif echo "$DEVICES" | grep -qi "ios\|iphone\|ipad\|simulator"; then
    # iOS simulator shares the host network stack
    HOST="127.0.0.1"
    DOCKER_BIND="127.0.0.1"
    echo "--> Detected iOS simulator — using host $HOST"
  else
    echo "warning: could not detect device type from 'flutter devices', defaulting to 127.0.0.1" >&2
    echo "$DEVICES" >&2
    HOST="127.0.0.1"
    DOCKER_BIND="127.0.0.1"
  fi
}

detect_host

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${ALL_VERSIONS[@]}")
fi

PASS=()
FAIL=()
CONTAINER_NAME="crg-scoreboard-test"

cleanup() {
  docker rm -f "$CONTAINER_NAME" &>/dev/null || true
}
trap cleanup EXIT

run_tests_for() {
  local VERSION="$1"
  local IMAGE="crg-scoreboard:$VERSION"

  echo ""
  echo "========================================"
  echo " Testing against $IMAGE"
  echo "========================================"

  if ! docker image inspect "$IMAGE" &>/dev/null; then
    echo "error: image $IMAGE not found — run build-scoreboard-images.sh first" >&2
    FAIL+=("$VERSION (image missing)")
    return
  fi

  cleanup

  echo "--> Starting $IMAGE on $DOCKER_BIND:$PORT (device will connect via $HOST:$PORT)"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --publish "$DOCKER_BIND:$PORT:8000" \
    "$IMAGE"

  # Wait for the scoreboard HTTP port to be ready (check from the host side)
  echo "--> Waiting for scoreboard to be ready..."
  local ATTEMPTS=0
  until curl -sf "http://127.0.0.1:$PORT/" -o /dev/null 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ $ATTEMPTS -ge 30 ]; then
      echo "error: scoreboard did not become ready after 30s" >&2
      docker logs "$CONTAINER_NAME" >&2
      FAIL+=("$VERSION (startup timeout)")
      cleanup
      return
    fi
    sleep 1
  done
  echo "--> Scoreboard ready"

  echo "--> Running integration tests"
  local EXIT_CODE=0
  flutter test integration_test/scoreboard_integration_test.dart \
    --dart-define=SCOREBOARD_HOST="$HOST" \
    --dart-define=SCOREBOARD_PORT="$PORT" \
    "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
    || EXIT_CODE=$?

  cleanup

  if [ $EXIT_CODE -eq 0 ]; then
    PASS+=("$VERSION")
    echo "--> PASS: $VERSION"
  else
    FAIL+=("$VERSION")
    echo "--> FAIL: $VERSION (exit code $EXIT_CODE)"
  fi
}

for VERSION in "${VERSIONS[@]}"; do
  run_tests_for "$VERSION"
done

echo ""
echo "========================================"
echo " Results"
echo "========================================"
for V in "${PASS[@]+"${PASS[@]}"}"; do
  echo "  PASS  $V"
done
for V in "${FAIL[@]+"${FAIL[@]}"}"; do
  echo "  FAIL  $V"
done

if [ ${#FAIL[@]} -gt 0 ]; then
  exit 1
fi