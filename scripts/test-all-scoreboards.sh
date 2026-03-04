#!/bin/bash
# Run integration tests against each scoreboard Docker image using 2 Android
# emulators in parallel to roughly halve the total run time.
# Run build-scoreboard-images.sh first.
#
# Usage: ./scripts/test-all-scoreboards.sh [options] [-- flutter test args]
#
# Options:
#   --versions  Comma-separated list of versions to test (default: all)
#   --avds      Comma-separated pair of AVD names for the two emulators
#               (default: first 2 from `emulator -list-avds`)
#   --host      Override the host address the tests connect to (default: 10.0.2.2)
#   --port      Base Docker host port; slot 1 uses PORT, slot 2 uses PORT+1
#               (default: 8001)
#
# Emulator handling:
#   If 2+ Android emulators are already running the script uses the first two.
#   Otherwise it starts the specified (or auto-detected) AVDs on console ports
#   5554 and 5556 and waits for them to boot. Emulators are left running after
#   the script exits.
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
AVD1=""
AVD2=""
HOST="10.0.2.2"
PORT=8001
FLUTTER_ARGS=()

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions) IFS=',' read -ra VERSIONS <<< "$2"; shift 2 ;;
    --avds)
      IFS=',' read -ra _AVDS <<< "$2"
      AVD1="${_AVDS[0]:-}"
      AVD2="${_AVDS[1]:-}"
      shift 2 ;;
    --host)  HOST="$2"; shift 2 ;;
    --port)  PORT="$2"; shift 2 ;;
    --)      shift; FLUTTER_ARGS=("$@"); break ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${ALL_VERSIONS[@]}")
fi

PORT2=$((PORT + 1))

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
  local AVD="$1" EMU_PORT="$2"
  echo "--> Starting AVD '$AVD' on console port $EMU_PORT"
  "$EMULATOR_BIN" -avd "$AVD" -port "$EMU_PORT" -no-audio -no-boot-anim -no-snapshot \
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

# Resolve SERIAL1 and SERIAL2 — reuse running emulators or start new ones.
ensure_emulators() {
  local RUNNING=()
  while IFS= read -r S; do [[ -n "$S" ]] && RUNNING+=("$S"); done \
    < <(running_emulators)

  if [[ ${#RUNNING[@]} -ge 2 ]]; then
    SERIAL1="${RUNNING[0]}"
    SERIAL2="${RUNNING[1]}"
    echo "--> Using already-running emulators: $SERIAL1  $SERIAL2"
    return
  fi

  # Resolve AVD names if not provided
  if [[ -z "$AVD1" || -z "$AVD2" ]]; then
    local AVDS=()
    while IFS= read -r A; do [[ -n "$A" ]] && AVDS+=("$A"); done \
      < <("$EMULATOR_BIN" -list-avds 2>/dev/null || true)
    [[ -z "$AVD1" ]] && AVD1="${AVDS[0]:-}"
    [[ -z "$AVD2" ]] && AVD2="${AVDS[1]:-}"
  fi

  if [[ -z "$AVD1" || -z "$AVD2" ]]; then
    echo "error: need 2 AVDs but none found — use --avds avd1,avd2" >&2
    exit 1
  fi

  if [[ ${#RUNNING[@]} -eq 0 ]]; then
    start_emulator "$AVD1" 5554
    start_emulator "$AVD2" 5556
    wait_for_emulator "emulator-5554"
    wait_for_emulator "emulator-5556"
    SERIAL1="emulator-5554"
    SERIAL2="emulator-5556"
  else
    # One already running — keep it, start one more on the free port
    SERIAL1="${RUNNING[0]}"
    local USED_PORT="${SERIAL1#emulator-}"
    local NEW_PORT; [[ "$USED_PORT" == "5554" ]] && NEW_PORT=5556 || NEW_PORT=5554
    start_emulator "$AVD2" "$NEW_PORT"
    wait_for_emulator "emulator-$NEW_PORT"
    SERIAL2="emulator-$NEW_PORT"
    echo "--> Using $SERIAL1 (existing) + $SERIAL2 (new)"
  fi
}

# ---------------------------------------------------------------------------
# Per-slot test runner
# ---------------------------------------------------------------------------
# run_slot SLOT SERIAL SLOT_PORT RESULT_FILE VERSION...
#
# Runs each VERSION sequentially on SERIAL against a Docker container on
# SLOT_PORT. Writes "PASS <version>" or "FAIL <version> (<reason>)" to
# RESULT_FILE. Flutter test output is captured; shown only on failure.
run_slot() {
  local SLOT="$1" SERIAL="$2" SLOT_PORT="$3" RESULT_FILE="$4"
  shift 4
  local SLOT_VERSIONS=("$@")
  local CONTAINER="crg-scoreboard-test-$SLOT"
  local TAG="[slot $SLOT]"

  for VERSION in "${SLOT_VERSIONS[@]}"; do
    local IMAGE="crg-scoreboard:$VERSION"

    echo ""
    echo "$TAG ========================================"
    echo "$TAG  $IMAGE  (device: $SERIAL  port: $SLOT_PORT)"
    echo "$TAG ========================================"

    if ! docker image inspect "$IMAGE" &>/dev/null; then
      echo "$TAG error: image $IMAGE not found — run build-scoreboard-images.sh first" >&2
      echo "FAIL $VERSION (image missing)" >> "$RESULT_FILE"
      continue
    fi

    docker rm -f "$CONTAINER" &>/dev/null || true

    echo "$TAG --> Starting $IMAGE on 0.0.0.0:$SLOT_PORT"
    docker run -d \
      --name "$CONTAINER" \
      --publish "0.0.0.0:$SLOT_PORT:8000" \
      "$IMAGE"

    echo "$TAG --> Waiting for scoreboard to be ready..."
    local ATTEMPTS=0 READY=true
    until curl -sf "http://127.0.0.1:$SLOT_PORT/" -o /dev/null 2>/dev/null; do
      ATTEMPTS=$((ATTEMPTS + 1))
      if [ $ATTEMPTS -ge 30 ]; then
        echo "$TAG error: scoreboard did not start within 30s" >&2
        docker logs "$CONTAINER" >&2
        echo "FAIL $VERSION (startup timeout)" >> "$RESULT_FILE"
        docker rm -f "$CONTAINER" &>/dev/null || true
        READY=false
        break
      fi
      sleep 1
    done
    [[ "$READY" == false ]] && continue
    echo "$TAG --> Scoreboard ready"

    echo "$TAG --> Running tests"
    local TEST_LOG="$RESULT_DIR/slot${SLOT}_${VERSION}.log"
    local EXIT_CODE=0
    flutter test integration_test/scoreboard_integration_test.dart \
      -d "$SERIAL" \
      --dart-define=SCOREBOARD_HOST="$HOST" \
      --dart-define=SCOREBOARD_PORT="$SLOT_PORT" \
      --dart-define=SCOREBOARD_VERSION="$VERSION" \
      "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
      > "$TEST_LOG" 2>&1 \
      || EXIT_CODE=$?

    docker rm -f "$CONTAINER" &>/dev/null || true

    if [ $EXIT_CODE -eq 0 ]; then
      echo "PASS $VERSION" >> "$RESULT_FILE"
      echo "$TAG --> PASS: $VERSION"
    else
      echo "FAIL $VERSION" >> "$RESULT_FILE"
      echo "$TAG --> FAIL: $VERSION (exit $EXIT_CODE)"
      echo "$TAG --> Test output:"
      cat "$TEST_LOG"
    fi
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

SERIAL1=""
SERIAL2=""
ensure_emulators

# Split versions roughly in half (slot 1 gets the extra for odd counts)
TOTAL=${#VERSIONS[@]}
HALF=$(( (TOTAL + 1) / 2 ))
VERSIONS_1=("${VERSIONS[@]:0:$HALF}")
VERSIONS_2=("${VERSIONS[@]:$HALF}")

echo ""
echo "--> Slot 1: $SERIAL1  port $PORT   versions: ${VERSIONS_1[*]}"
if [[ ${#VERSIONS_2[@]} -gt 0 ]]; then
  echo "--> Slot 2: $SERIAL2  port $PORT2  versions: ${VERSIONS_2[*]}"
else
  echo "--> Slot 2: $SERIAL2  (no versions assigned)"
fi

RESULT_DIR=$(mktemp -d)
RESULT_FILE_1="$RESULT_DIR/slot1"
RESULT_FILE_2="$RESULT_DIR/slot2"
touch "$RESULT_FILE_1" "$RESULT_FILE_2"

cleanup() {
  docker rm -f "crg-scoreboard-test-1" "crg-scoreboard-test-2" &>/dev/null || true
  rm -rf "$RESULT_DIR"
}
trap cleanup EXIT

# Run both slots in parallel
PID1="" PID2=""
run_slot 1 "$SERIAL1" "$PORT"  "$RESULT_FILE_1" "${VERSIONS_1[@]}" &
PID1=$!

if [[ ${#VERSIONS_2[@]} -gt 0 ]]; then
  run_slot 2 "$SERIAL2" "$PORT2" "$RESULT_FILE_2" "${VERSIONS_2[@]}" &
  PID2=$!
fi

SLOT1_EXIT=0 SLOT2_EXIT=0
wait "$PID1" || SLOT1_EXIT=$?
[[ -n "$PID2" ]] && { wait "$PID2" || SLOT2_EXIT=$?; }

# Merge and report results
PASS=()
FAIL=()
while IFS=' ' read -r STATUS VERSION_REST; do
  [[ -z "${STATUS:-}" ]] && continue
  if [[ "$STATUS" == "PASS" ]]; then
    PASS+=("$VERSION_REST")
  else
    FAIL+=("$VERSION_REST")
  fi
done < <(cat "$RESULT_FILE_1" "$RESULT_FILE_2")

echo ""
echo "========================================"
echo " Results"
echo "========================================"
for V in "${PASS[@]+"${PASS[@]}"}"; do echo "  PASS  $V"; done
for V in "${FAIL[@]+"${FAIL[@]}"}"; do echo "  FAIL  $V"; done

if [ ${#FAIL[@]} -gt 0 ]; then
  exit 1
fi