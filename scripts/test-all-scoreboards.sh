#!/bin/bash
# Run integration tests against each scoreboard Docker image. Available Android
# emulators can run independent version workers in parallel.
# Run build-scoreboard-images.sh first.
#
# Usage: ./scripts/test-all-scoreboards.sh [options] [-- flutter test args]
#
# Options:
#   --versions  Comma-separated list of versions to test (default: all, newest first)
#   --avd       AVD name to use (default: first from `emulator -list-avds`)
#   --host      Override the host address the tests connect to (default: 10.0.2.2)
#   --port      First Docker host port to try (default: 8001)
#   --jobs      Maximum emulator workers to use (default: all running emulators)
#   --results-dir  Parent directory for local reports (default: test-results)
#   --no-html      Leave Allure result files without generating an HTML report
#
# Emulator handling:
#   If Android emulators are already running the script uses them.
#   Otherwise it starts the specified (or auto-detected) AVD on console port
#   5554 and waits for it to boot. The emulator is left running after the
#   script exits.
#
# Passes any args after -- directly to flutter test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scoreboard-test-runner.sh"

VERSIONS=()
AVD=""
HOST="10.0.2.2"
PORT=8001
PORT_STRIDE=""
JOBS=""
DEVICE=""
RESULTS_DIR="test-results"
GENERATE_HTML=true
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
    --port-stride) PORT_STRIDE="$2"; shift 2 ;;
    --jobs)  JOBS="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --no-html) GENERATE_HTML=false; shift ;;
    --)      shift; FLUTTER_ARGS=("$@"); break ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$JOBS" ]]; then
  scoreboard_require_positive_integer --jobs "$JOBS" || exit 1
fi
scoreboard_require_valid_port "$PORT" || exit 1
scoreboard_require_port_finder || exit 1

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${SCOREBOARD_ALL_VERSIONS[@]}")
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="$RESULTS_DIR/scoreboard-integration-$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
ALLURE_RESULTS_DIR="$RUN_DIR/allure-results"
FLUTTER_RESULTS_DIR="$RUN_DIR/flutter-results"
ALLURE_REPORT_DIR="$RUN_DIR/allure-report"
mkdir -p "$LOG_DIR" "$ALLURE_RESULTS_DIR" "$FLUTTER_RESULTS_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
LOG_DIR="$RUN_DIR/logs"
ALLURE_RESULTS_DIR="$RUN_DIR/allure-results"
FLUTTER_RESULTS_DIR="$RUN_DIR/flutter-results"
ALLURE_REPORT_DIR="$RUN_DIR/allure-report"

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
  "$ADB_BIN" devices 2>/dev/null | awk '$1 ~ /^emulator-/ && $2 == "device" {print $1}' || true
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

# Resolve EMULATORS — reuse all running emulators, or start one if needed.
ensure_emulators() {
  local RUNNING=()
  EMULATORS=()

  if [[ -n "$DEVICE" ]]; then
    if ! "$ADB_BIN" devices 2>/dev/null | awk '$2 == "device" {print $1}' | grep -qx "$DEVICE"; then
      echo "error: requested emulator $DEVICE is not running" >&2
      exit 1
    fi
    EMULATORS=("$DEVICE")
    return
  fi

  while IFS= read -r S; do [[ -n "$S" ]] && RUNNING+=("$S"); done \
    < <(running_emulators)

  if [[ ${#RUNNING[@]} -ge 1 ]]; then
    EMULATORS=("${RUNNING[@]}")
    echo "--> Using already-running emulators: ${EMULATORS[*]}"
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
  EMULATORS=("emulator-5554")
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ensure_emulators

if [[ -z "$JOBS" ]]; then
  JOBS=${#EMULATORS[@]}
fi
if (( JOBS > ${#EMULATORS[@]} )); then
  echo "--> Capping --jobs $JOBS to ${#EMULATORS[@]} available emulator(s)"
  JOBS=${#EMULATORS[@]}
fi
if (( JOBS > ${#VERSIONS[@]} )); then
  JOBS=${#VERSIONS[@]}
fi

if [[ -z "$PORT_STRIDE" ]]; then
  PORT_STRIDE="$JOBS"
fi
scoreboard_require_positive_integer --port-stride "$PORT_STRIDE" || exit 1

WORKER_PORTS=()
for (( worker=0; worker<JOBS; worker++ )); do
  worker_port="$(scoreboard_find_available_port "$((PORT + worker))" "$PORT_STRIDE")" || exit 1
  WORKER_PORTS+=("$worker_port")
done

run_fanout() {
  local worker version worker_port worker_device worker_dir worker_results_dir
  local index worker_exit overall_exit=0
  local PIDS=()

  if ! command -v rsync &>/dev/null; then
    echo "error: rsync is required to isolate parallel Flutter test workers" >&2
    return 1
  fi

  mkdir -p "$RUN_DIR/workers" "$RUN_DIR/status"
  echo ""
  echo "--> Testing ${#VERSIONS[@]} version(s) on $JOBS emulator worker(s)"
  echo "--> Emulators: ${EMULATORS[*]:0:JOBS}"
  echo "--> Worker ports: ${WORKER_PORTS[*]}"
  echo "--> Flutter workers use isolated copies of the current checkout"
  echo "--> Run directory: $RUN_DIR"

  run_worker() {
    local worker_index="$1"
    local version_index="$worker_index"
    local result=0
    local local_worker_dir

    local_worker_dir="$(mktemp -d /private/tmp/jamready-scoreboard-integration.XXXXXX)"
    if ! rsync -a \
      --exclude '.git' \
      --exclude '.dart_tool' \
      --exclude 'build' \
      --exclude 'test-results' \
      --exclude 'allure-results' \
      --exclude 'flutter_*.log' \
      "$SCRIPT_DIR/../" "$local_worker_dir/"; then
      echo "error: failed to create isolated checkout for ${EMULATORS[worker_index]}" >&2
      return 1
    fi

    if ! (cd "$local_worker_dir" && flutter pub get); then
      echo "error: flutter pub get failed for ${EMULATORS[worker_index]}" >&2
      rm -rf "$local_worker_dir"
      return 1
    fi

    while (( version_index < ${#VERSIONS[@]} )); do
      local version="${VERSIONS[version_index]}"
      local worker_results="$RUN_DIR/workers/$version"
      local exit_code=0
      mkdir -p "$worker_results"

      echo "Beginning UI integration tests for ${version} in directory ${local_worker_dir}"

      (
        cd "$local_worker_dir"
        ./scripts/test-all-scoreboards.sh \
          --versions "$version" \
          --device "${EMULATORS[worker_index]}" \
          --host "$HOST" \
          --port "${WORKER_PORTS[worker_index]}" \
          --port-stride "$PORT_STRIDE" \
          --jobs 1 \
          --results-dir "$worker_results" \
          --no-html \
          -- "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}"
      ) >"$LOG_DIR/$version.log" 2>&1 || exit_code=$?

      if [ "$exit_code" -eq 0 ]; then
        printf 'PASS\n' >"$RUN_DIR/status/$version"
      else
        printf 'FAIL\n' >"$RUN_DIR/status/$version"
        result=1
      fi

      echo "Finished UI integration test for ${version}; exit code: ${exit_code}"

      version_index=$((version_index + JOBS))
    done

    rm -rf "$local_worker_dir"
    return "$result"
  }

  for (( worker=0; worker<JOBS; worker++ )); do
    run_worker "$worker" &
    PIDS+=("$!")
  done
  for worker in "${PIDS[@]}"; do
    wait "$worker" || overall_exit=1
  done

  echo ""
  echo "========================================"
  echo " Scoreboard integration test summary"
  echo "========================================"
  for version in "${VERSIONS[@]}"; do
    local status
    status="$(cat "$RUN_DIR/status/$version" 2>/dev/null || echo FAIL)"
    printf '  %-4s  %s\n' "$status" "$version"
    [[ "$status" == PASS ]] || overall_exit=1
  done

  if "$GENERATE_HTML"; then
    local allure_inputs=()
    while IFS= read -r allure_input; do
      allure_inputs+=("$allure_input")
    done < <(find "$RUN_DIR/workers" -type f -name '*-result.json' \
      -exec dirname {} \; | sort -u)
    echo "--> Generating Allure HTML report"
    if scoreboard_generate_allure_report "$ALLURE_REPORT_DIR" "${allure_inputs[@]+"${allure_inputs[@]}"}"; then
      echo "--> Allure report: $ALLURE_REPORT_DIR/index.html"
    else
      echo "--> Raw Allure results: $RUN_DIR/workers" >&2
      overall_exit=1
    fi
  else
    echo "--> Raw Allure results: $RUN_DIR/workers"
  fi

  if [ "$overall_exit" -ne 0 ]; then
    echo ""
    echo "========================================"
    echo " Failed version logs"
    echo "========================================"
    for version in "${VERSIONS[@]}"; do
      if [[ "$(cat "$RUN_DIR/status/$version" 2>/dev/null || echo FAIL)" != PASS ]]; then
        echo "--- BEGIN $version ---"
        cat "$LOG_DIR/$version.log" 2>/dev/null || true
        echo "--- END $version ---"
      fi
    done
  fi

  return "$overall_exit"
}

if (( JOBS > 1 )) && [[ -z "$DEVICE" ]]; then
  run_fanout
  exit $?
fi

SERIAL="${EMULATORS[0]}"
PORT="${WORKER_PORTS[0]}"

CONTAINER="crg-scoreboard-test-$RUN_ID"

cleanup() {
  docker rm -f "$CONTAINER" &>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "--> Testing ${#VERSIONS[@]} version(s) on $SERIAL  port $PORT"
echo "--> Versions: ${VERSIONS[*]}"
echo "--> Run directory: $RUN_DIR"

PASS=()
FAIL=()
OVERALL_EXIT=0

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

  while true; do
    if ! scoreboard_port_is_available "$PORT"; then
      echo "--> Port $PORT is in use; trying another port"
      PORT="$(scoreboard_find_available_port "$((PORT + PORT_STRIDE))" "$PORT_STRIDE")" || exit 1
      continue
    fi

    echo "--> Starting $IMAGE on 0.0.0.0:$PORT"
    if docker run -d \
      --name "$CONTAINER" \
      --publish "0.0.0.0:$PORT:8000" \
      "$IMAGE"; then
      break
    fi

    # A process can claim the port after lsof checks it. Remove Docker's
    # failed container and retry the next port in this worker's stride.
    docker rm -f "$CONTAINER" &>/dev/null || true
    echo "--> Docker could not bind port $PORT; trying another port"
    PORT="$(scoreboard_find_available_port "$((PORT + PORT_STRIDE))" "$PORT_STRIDE")" || exit 1
  done

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
  TEST_LOG="$LOG_DIR/$VERSION.log"
  VERSION_ALLURE_RESULTS_DIR="$ALLURE_RESULTS_DIR/$VERSION"
  VERSION_FLUTTER_RESULTS_FILE="$FLUTTER_RESULTS_DIR/$VERSION.json"
  mkdir -p "$VERSION_ALLURE_RESULTS_DIR"
  EXIT_CODE=0
  flutter test integration_test/scoreboard_integration_test.dart \
    -d "$SERIAL" \
    --dart-define=SCOREBOARD_HOST="$HOST" \
    --dart-define=SCOREBOARD_PORT="$PORT" \
    --dart-define=SCOREBOARD_VERSION="$VERSION" \
    --file-reporter="json:$VERSION_FLUTTER_RESULTS_FILE" \
    "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
    > "$TEST_LOG" 2>&1 \
    || EXIT_CODE=$?

  if ! node "$SCRIPT_DIR/flutter-json-to-allure.mjs" \
    --input "$VERSION_FLUTTER_RESULTS_FILE" \
    --output "$VERSION_ALLURE_RESULTS_DIR" \
    --version "$VERSION"; then
    echo "error: failed to convert Flutter JSON results for $VERSION" >&2
    EXIT_CODE=1
  fi

  docker rm -f "$CONTAINER" &>/dev/null || true

  if [ $EXIT_CODE -eq 0 ]; then
    PASS+=("$VERSION")
    echo "--> PASS: $VERSION (log: $TEST_LOG)"
  else
    echo "--> FAIL: $VERSION (exit $EXIT_CODE, log: $TEST_LOG)"
    FAIL+=("$VERSION")
    OVERALL_EXIT=1
  fi
done

echo ""
echo "========================================"
echo " Scoreboard integration test summary"
echo "========================================"
for V in "${PASS[@]+"${PASS[@]}"}"; do echo "  PASS  $V"; done
for V in "${FAIL[@]+"${FAIL[@]}"}"; do echo "  FAIL  $V"; done
if "$GENERATE_HTML"; then
  ALLURE_INPUTS=()
  while IFS= read -r allure_input; do
    ALLURE_INPUTS+=("$allure_input")
  done < <(find "$ALLURE_RESULTS_DIR" -type f -name '*-result.json' \
    -exec dirname {} \; | sort -u)
  echo "--> Generating Allure HTML report"
  if scoreboard_generate_allure_report "$ALLURE_REPORT_DIR" "${ALLURE_INPUTS[@]+"${ALLURE_INPUTS[@]}"}"; then
    echo "--> Allure report: $ALLURE_REPORT_DIR/index.html"
  else
    echo "--> Raw Allure results: $ALLURE_RESULTS_DIR" >&2
    OVERALL_EXIT=1
  fi
else
  echo "--> Raw Allure results: $ALLURE_RESULTS_DIR"
fi

if [ "$OVERALL_EXIT" -ne 0 ]; then
  echo ""
  echo "========================================"
  echo " Failed version logs"
  echo "========================================"
  for V in "${FAIL[@]+"${FAIL[@]}"}"; do
    echo "--- BEGIN $V ---"
    cat "$LOG_DIR/$V.log" 2>/dev/null || true
    echo "--- END $V ---"
  done
fi

exit "$OVERALL_EXIT"
