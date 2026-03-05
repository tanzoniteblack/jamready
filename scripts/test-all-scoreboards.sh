#!/bin/bash
# Run integration tests against each scoreboard Docker image sequentially,
# newest version first. Stops on the first failure.
# Run build-scoreboard-images.sh first.
#
# Usage: ./scripts/test-all-scoreboards.sh [options] [-- flutter test args]
#
# Options:
#   --versions  Comma-separated list of versions to test (default: all, newest first)
#   --avd       AVD name to use (default: first from `emulator -list-avds`)
#   --host      Override the host address the tests connect to (default: 10.0.2.2)
#   --port      Docker host port for the scoreboard container (default: 8001)
#
# Emulator handling:
#   If an Android emulator is already running the script uses it.
#   Otherwise it starts the specified (or auto-detected) AVD on console port
#   5554 and waits for it to boot. The emulator is left running after the
#   script exits.
#
# Passes any args after -- directly to flutter test.

set -euo pipefail

ALL_VERSIONS=(
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
  v2023.7
)

VERSIONS=()
AVD=""
HOST="10.0.2.2"
PORT=8001
FLUTTER_ARGS=()

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions) IFS=',' read -ra VERSIONS <<< "$2"; shift 2 ;;
    --avd)   AVD="$2"; shift 2 ;;
    --host)  HOST="$2"; shift 2 ;;
    --port)  PORT="$2"; shift 2 ;;
    --)      shift; FLUTTER_ARGS=("$@"); break ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${ALL_VERSIONS[@]}")
fi

# ---------------------------------------------------------------------------
# Emulator helpers
# ---------------------------------------------------------------------------

# Resolve the Android emulator binary.
# Checks PATH first, then common SDK locations on macOS and Linux.
find_emulator_bin() {
  if command -v emulator &>/dev/null; then
    echo "emulator"; return
  fi
  local CANDIDATES=(
    "${ANDROID_HOME:-}/emulator/emulator"
    "${ANDROID_SDK_ROOT:-}/emulator/emulator"
    "$HOME/Library/Android/sdk/emulator/emulator"
    "$HOME/Android/Sdk/emulator/emulator"
  )
  for BIN in "${CANDIDATES[@]}"; do
    [[ -x "$BIN" ]] && { echo "$BIN"; return; }
  done
  echo ""
}

# Resolve the Android adb binary.
find_adb_bin() {
  if command -v adb &>/dev/null; then
    echo "adb"; return
  fi
  local CANDIDATES=(
    "${ANDROID_HOME:-}/platform-tools/adb"
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb"
    "$HOME/Library/Android/sdk/platform-tools/adb"
    "$HOME/Android/Sdk/platform-tools/adb"
  )
  for BIN in "${CANDIDATES[@]}"; do
    [[ -x "$BIN" ]] && { echo "$BIN"; return; }
  done
  echo ""
}

EMULATOR_BIN=$(find_emulator_bin)
if [[ -z "$EMULATOR_BIN" ]]; then
  echo "error: Android emulator binary not found — add it to PATH or set ANDROID_HOME" >&2
  exit 1
fi

ADB_BIN=$(find_adb_bin)
if [[ -z "$ADB_BIN" ]]; then
  echo "error: adb not found — add it to PATH or set ANDROID_HOME" >&2
  exit 1
fi

# Print serials of running Android emulators, one per line.
running_emulators() {
  "$ADB_BIN" devices 2>/dev/null | awk '/^emulator-/{print $1}' || true
}

# Start an emulator on a fixed console port (serial will be emulator-<port>).
# Runs in the background; call wait_for_emulator to block until it's ready.
start_emulator() {
  local AVD_NAME="$1" EMU_PORT="$2"
  echo "--> Starting AVD '$AVD_NAME' on console port $EMU_PORT"
  "$EMULATOR_BIN" -avd "$AVD_NAME" -port "$EMU_PORT" -no-audio -no-boot-anim -no-snapshot \
    </dev/null &>/dev/null &
  disown
}

# Block until the emulator has fully booted into Android.
wait_for_emulator() {
  local SERIAL="$1"
  echo "--> Waiting for $SERIAL to boot..."
  "$ADB_BIN" -s "$SERIAL" wait-for-device shell \
    'until getprop sys.boot_completed 2>/dev/null | grep -q "^1$"; do sleep 3; done' \
    &>/dev/null
  echo "--> $SERIAL is ready"
}

# Resolve SERIAL — reuse a running emulator or start a new one.
ensure_emulator() {
  local RUNNING=()
  while IFS= read -r S; do [[ -n "$S" ]] && RUNNING+=("$S"); done \
    < <(running_emulators)

  if [[ ${#RUNNING[@]} -ge 1 ]]; then
    SERIAL="${RUNNING[0]}"
    echo "--> Using already-running emulator: $SERIAL"
    return
  fi

  # Resolve AVD name if not provided
  if [[ -z "$AVD" ]]; then
    local AVDS=()
    while IFS= read -r A; do [[ -n "$A" ]] && AVDS+=("$A"); done \
      < <("$EMULATOR_BIN" -list-avds 2>/dev/null || true)
    AVD="${AVDS[0]:-}"
  fi

  if [[ -z "$AVD" ]]; then
    echo "error: no AVD found — use --avd <name>" >&2
    exit 1
  fi

  start_emulator "$AVD" 5554
  wait_for_emulator "emulator-5554"
  SERIAL="emulator-5554"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

SERIAL=""
ensure_emulator

CONTAINER="crg-scoreboard-test"

cleanup() {
  docker rm -f "$CONTAINER" &>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "--> Testing ${#VERSIONS[@]} version(s) on $SERIAL  port $PORT"
echo "--> Versions: ${VERSIONS[*]}"

PASS=()

for VERSION in "${VERSIONS[@]}"; do
  IMAGE="crg-scoreboard:$VERSION"

  echo ""
  echo "========================================"
  echo "  $IMAGE  (device: $SERIAL  port: $PORT)"
  echo "========================================"

  if ! docker image inspect "$IMAGE" &>/dev/null; then
    echo "error: image $IMAGE not found — run build-scoreboard-images.sh first" >&2
    exit 1
  fi

  docker rm -f "$CONTAINER" &>/dev/null || true

  echo "--> Starting $IMAGE on 0.0.0.0:$PORT"
  docker run -d \
    --name "$CONTAINER" \
    --publish "0.0.0.0:$PORT:8000" \
    "$IMAGE"

  echo "--> Waiting for scoreboard to be ready..."
  ATTEMPTS=0
  until curl -sf "http://127.0.0.1:$PORT/" -o /dev/null 2>/dev/null; do
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ $ATTEMPTS -ge 30 ]; then
      echo "error: scoreboard did not start within 30s" >&2
      docker logs "$CONTAINER" >&2
      exit 1
    fi
    sleep 1
  done
  echo "--> Scoreboard ready"

  echo "--> Running tests"
  TEST_LOG=$(mktemp)
  EXIT_CODE=0
  flutter test integration_test/scoreboard_integration_test.dart \
    -d "$SERIAL" \
    --dart-define=SCOREBOARD_HOST="$HOST" \
    --dart-define=SCOREBOARD_PORT="$PORT" \
    --dart-define=SCOREBOARD_VERSION="$VERSION" \
    "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
    > "$TEST_LOG" 2>&1 \
    || EXIT_CODE=$?

  docker rm -f "$CONTAINER" &>/dev/null || true

  if [ $EXIT_CODE -eq 0 ]; then
    PASS+=("$VERSION")
    echo "--> PASS: $VERSION"
    rm -f "$TEST_LOG"
  else
    echo "--> FAIL: $VERSION (exit $EXIT_CODE)"
    echo "--> Test output:"
    cat "$TEST_LOG"
    rm -f "$TEST_LOG"
    echo ""
    echo "========================================"
    echo " Stopped at first failure"
    echo "========================================"
    for V in "${PASS[@]+"${PASS[@]}"}"; do echo "  PASS  $V"; done
    echo "  FAIL  $VERSION"
    exit 1
  fi
done

echo ""
echo "========================================"
echo " All versions passed"
echo "========================================"
for V in "${PASS[@]+"${PASS[@]}"}"; do echo "  PASS  $V"; done
