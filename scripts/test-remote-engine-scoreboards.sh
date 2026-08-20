#!/bin/bash
# Run remote_engine_test/ against each scoreboard Docker image. Local runs can
# fan out across versions and produce a combined, browsable Allure report.
# GitHub Actions keeps its existing JSON reports for dorny/test-reporter.
#
# Run build-scoreboard-images.sh first.
#
# Usage: ./scripts/test-remote-engine-scoreboards.sh [options] [-- flutter test args]
#
# Options:
#   --versions     Comma-separated list of versions to test (default: all, newest first)
#   --host         Host address the tests connect to (default: 127.0.0.1)
#   --port         First Docker host port to try (default: 8001)
#   --jobs         Versions to run in parallel locally (default: 1)
#   --results-dir  Parent directory for reports (default: test-results)
#   --no-html      Leave Allure result files without generating an HTML report
#
# Local reports are written to
#   <results-dir>/remote-engine-<timestamp>-<pid>/allure-report/index.html
# along with per-version logs and raw Allure result files. Generating the HTML
# report requires Node.js 20+ and uses `npx -y allure@3`.
#
# Passes any args after -- directly to flutter test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLURE_CONFIG="$SCRIPT_DIR/../allurerc.mjs"

ALL_VERSIONS=(
  # Seattle Derby Brats' temporary server-authoritative penalty-box fork.
  feature-pbt
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
HOST="127.0.0.1"
PORT=8001
PORT_STRIDE=""
JOBS=1
RESULTS_DIR="test-results"
GENERATE_HTML=true
FLUTTER_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions)    IFS=',' read -ra VERSIONS <<< "$2"; shift 2 ;;
    --host)        HOST="$2"; shift 2 ;;
    --port)        PORT="$2"; shift 2 ;;
    --port-stride) PORT_STRIDE="$2"; shift 2 ;;
    --jobs)        JOBS="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --no-html)     GENERATE_HTML=false; shift ;;
    --)            shift; FLUTTER_ARGS=("$@"); break ;;
    *)             echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --jobs must be a positive integer" >&2
  exit 1
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "error: --port must be a valid TCP port" >&2
  exit 1
fi

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${ALL_VERSIONS[@]}")
fi

if (( JOBS > ${#VERSIONS[@]} )); then
  JOBS=${#VERSIONS[@]}
fi

if [[ -z "$PORT_STRIDE" ]]; then
  PORT_STRIDE="$JOBS"
fi

if [[ ! "$PORT_STRIDE" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --port-stride must be a positive integer" >&2
  exit 1
fi

if ! command -v lsof &>/dev/null; then
  echo "error: lsof is required to find an available Docker host port" >&2
  exit 1
fi

# Returns success only when no process is listening on [port]. Docker publishes
# to 0.0.0.0, so checking every listening address avoids host-specific misses.
port_is_available() {
  ! lsof -nP -iTCP:"$1" -sTCP:LISTEN &>/dev/null
}

# Find a free port in one worker's stride. Each worker starts at a different
# offset and advances by JOBS, so workers cannot select the same fallback port.
find_available_port() {
  local candidate="$1"
  local stride="$2"

  while (( candidate <= 65535 )); do
    if port_is_available "$candidate"; then
      echo "$candidate"
      return
    fi
    candidate=$((candidate + stride))
  done

  echo "error: no available port found at or above $1" >&2
  return 1
}

WORKER_PORTS=()
for (( worker=0; worker<JOBS; worker++ )); do
  if ! worker_port="$(find_available_port "$((PORT + worker))" "$PORT_STRIDE")"; then
    exit 1
  fi
  WORKER_PORTS+=("$worker_port")
done

IS_CI=false
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  IS_CI=true
fi

ISOLATE_FLUTTER_WORKERS=false
if ! "$IS_CI" && (( JOBS > 1 )); then
  if ! command -v rsync &>/dev/null; then
    echo "error: rsync is required to isolate parallel Flutter test workers" >&2
    exit 1
  fi
  ISOLATE_FLUTTER_WORKERS=true
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="$RESULTS_DIR/remote-engine-$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
STATUS_DIR="$RUN_DIR/status"
ALLURE_RESULTS_DIR="$RUN_DIR/allure-results"
ALLURE_REPORT_DIR="$RUN_DIR/allure-report"

if "$IS_CI"; then
  # Preserve the current GitHub Actions contract: one JSON file per version in
  # test-results/, where dorny/test-reporter and upload-artifact expect it.
  mkdir -p "$RESULTS_DIR"
else
  mkdir -p "$LOG_DIR" "$STATUS_DIR" "$ALLURE_RESULTS_DIR"
  RUN_DIR="$(cd "$RUN_DIR" && pwd)"
  LOG_DIR="$RUN_DIR/logs"
  STATUS_DIR="$RUN_DIR/status"
  ALLURE_RESULTS_DIR="$RUN_DIR/allure-results"
  ALLURE_REPORT_DIR="$RUN_DIR/allure-report"
  mkdir -p "$RUN_DIR/workers"
fi

CONTAINERS=()
PIDS=()
WORKER_DIRS=()

cleanup() {
  local pid container worker_dir
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
    kill "$pid" 2>/dev/null || true
  done
  for container in "${CONTAINERS[@]+"${CONTAINERS[@]}"}"; do
    docker rm -f "$container" &>/dev/null || true
  done
  for worker_dir in "${WORKER_DIRS[@]+"${WORKER_DIRS[@]}"}"; do
    if [[ "$worker_dir" == /private/tmp/jamready-scoreboard.* ]]; then
      rm -rf "$worker_dir"
    fi
  done
}
trap cleanup EXIT INT TERM

run_version() {
  local version="$1"
  local worker_index="$2"
  local worker_port="${WORKER_PORTS[worker_index]}"
  local image="crg-scoreboard:$version"
  local safe_version="${version//[^a-zA-Z0-9_.-]/-}"
  local container="crg-scoreboard-remote-engine-${RUN_ID}-${worker_index}-${safe_version}"
  local log_file status_file report_file version_allure_dir
  local attempts=0 exit_code=0

  if "$IS_CI"; then
    log_file="$(mktemp)"
    report_file="$RESULTS_DIR/remote-engine-$version.json"
  else
    log_file="$LOG_DIR/$version.log"
    status_file="$STATUS_DIR/$version"
    version_allure_dir="$ALLURE_RESULTS_DIR/$version"
    mkdir -p "$version_allure_dir"
  fi

  CONTAINERS+=("$container")
  {
    echo "========================================"
    echo "  $image  (host: $HOST  port: $worker_port)"
    echo "========================================"

    if ! docker image inspect "$image" &>/dev/null; then
      echo "error: image $image not found — run build-scoreboard-images.sh first" >&2
      exit_code=1
    else
      while true; do
        if ! port_is_available "$worker_port"; then
          echo "--> Port $worker_port is in use; trying another port"
          worker_port="$(find_available_port "$((worker_port + PORT_STRIDE))" "$PORT_STRIDE")" || {
            exit_code=1
            break
          }
          continue
        fi

        echo "--> Starting $image on 0.0.0.0:$worker_port"
        if docker run -d --name "$container" --publish "0.0.0.0:$worker_port:8000" "$image"; then
          break
        fi

        # A process can claim the port after lsof checks it. Remove Docker's
        # failed container and retry the next port in this worker's stride.
        docker rm -f "$container" &>/dev/null || true
        echo "--> Docker could not bind port $worker_port; trying another port"
        worker_port="$(find_available_port "$((worker_port + PORT_STRIDE))" "$PORT_STRIDE")" || {
          exit_code=1
          break
        }
      done

      if [ "$exit_code" -eq 0 ]; then
        echo "--> Waiting for scoreboard to be ready..."
        until curl -sf "http://127.0.0.1:$worker_port/" -o /dev/null 2>/dev/null; do
          attempts=$((attempts + 1))
          if [ "$attempts" -ge 30 ]; then
            echo "error: scoreboard did not start within 30s" >&2
            docker logs "$container" >&2 || true
            exit_code=1
            break
          fi
          sleep 1
        done
      fi

      if [ "$exit_code" -eq 0 ]; then
        echo "--> Scoreboard ready"
        echo "--> Running tests"
        if "$IS_CI"; then
          flutter test remote_engine_test/ \
            --concurrency=1 \
            --dart-define=SCOREBOARD_HOST="$HOST" \
            --dart-define=SCOREBOARD_PORT="$worker_port" \
            --dart-define=SCOREBOARD_VERSION="$version" \
            --file-reporter="json:$report_file" \
            "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
            || exit_code=$?
        else
          ALLURE_RESULTS_DIR="$version_allure_dir" flutter test remote_engine_test/ \
            --concurrency=1 \
            --dart-define=SCOREBOARD_HOST="$HOST" \
            --dart-define=SCOREBOARD_PORT="$worker_port" \
            --dart-define=SCOREBOARD_VERSION="$version" \
            "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
            || exit_code=$?
        fi
      fi
    fi
  } >"$log_file" 2>&1

  docker rm -f "$container" &>/dev/null || true

  if "$IS_CI"; then
    cat "$log_file"
    rm -f "$log_file"
  elif [ "$exit_code" -eq 0 ]; then
    printf 'PASS\n' >"$status_file"
  else
    printf 'FAIL\n' >"$status_file"
  fi

  return "$exit_code"
}

run_version_in_copy() {
  local version="$1"
  local worker_index="$2"
  local worker_port="${WORKER_PORTS[worker_index]}"
  local worker_dir worker_results_dir exit_code=0

  worker_dir="$(mktemp -d /private/tmp/jamready-scoreboard.XXXXXX)"
  WORKER_DIRS+=("$worker_dir")
  worker_results_dir="$RUN_DIR/workers/$version"
  mkdir -p "$worker_results_dir"

  echo "Running tests for ${version} in work dir: ${worker_dir}"

  if ! rsync -a \
    --exclude '.git' \
    --exclude '.dart_tool' \
    --exclude 'build' \
    --exclude 'test-results' \
    --exclude 'allure-results' \
    --exclude 'flutter_*.log' \
    "$SCRIPT_DIR/../" "$worker_dir/"; then
    echo "error: failed to create isolated checkout for $version" >&2
    printf 'FAIL\n' >"$STATUS_DIR/$version"
    return 1
  fi

  (
    cd "$worker_dir"
    flutter pub get
    ./scripts/test-remote-engine-scoreboards.sh \
      --versions "$version" \
      --host "$HOST" \
      --port "$worker_port" \
      --port-stride "$PORT_STRIDE" \
      --jobs 1 \
      --results-dir "$worker_results_dir" \
      --no-html \
      "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}"
  ) >"$LOG_DIR/$version.log" 2>&1 || exit_code=$?

  rm -rf "$worker_dir"
  WORKER_DIRS=()

  if [ "$exit_code" -eq 0 ]; then
    printf 'PASS\n' >"$STATUS_DIR/$version"
  else
    printf 'FAIL\n' >"$STATUS_DIR/$version"
  fi

  echo "Finished running test for ${version} with status: ${exit_code}"

  return "$exit_code"
}

run_worker() {
  local worker_index="$1"
  local index="$worker_index"
  local worker_exit=0

  # This function runs in a background subshell. Do not inherit the parent's
  # worker PID list, or this worker's EXIT trap could terminate a sibling.
  PIDS=()

  while (( index < ${#VERSIONS[@]} )); do
    if "$ISOLATE_FLUTTER_WORKERS"; then
      run_version_in_copy "${VERSIONS[index]}" "$worker_index" || worker_exit=1
    else
      run_version "${VERSIONS[index]}" "$worker_index" || worker_exit=1
    fi
    index=$((index + JOBS))
  done

  return "$worker_exit"
}

echo
echo "--> Testing ${#VERSIONS[@]} version(s) on $HOST starting at port $PORT"
echo "--> Versions: ${VERSIONS[*]}"
echo "--> Worker ports: ${WORKER_PORTS[*]}"
if ! "$IS_CI"; then
  echo "--> Local workers: $JOBS"
  if "$ISOLATE_FLUTTER_WORKERS"; then
    echo "--> Flutter workers use isolated copies of the current checkout"
  fi
  echo "--> Run directory: $RUN_DIR"
fi

for (( worker=0; worker<JOBS; worker++ )); do
  run_worker "$worker" &
  PIDS+=("$!")
done

OVERALL_EXIT=0
for pid in "${PIDS[@]}"; do
  wait "$pid" || OVERALL_EXIT=1
done
PIDS=()

if "$IS_CI"; then
  exit "$OVERALL_EXIT"
fi

echo
echo "========================================"
echo " Remote engine test summary"
echo "========================================"
for version in "${VERSIONS[@]}"; do
  status="$(cat "$STATUS_DIR/$version" 2>/dev/null || echo FAIL)"
  printf '  %-4s  %s\n' "$status" "$version"
  if [[ "$status" != PASS ]]; then
    OVERALL_EXIT=1
  fi
done

if "$GENERATE_HTML"; then
  if ! command -v npx &>/dev/null; then
    echo "error: npx is required to generate the Allure HTML report" >&2
    echo "--> Raw Allure results: $ALLURE_RESULTS_DIR" >&2
    exit 1
  fi

  echo "--> Generating Allure HTML report"
  ALLURE_INPUTS=("$ALLURE_RESULTS_DIR")
  if "$ISOLATE_FLUTTER_WORKERS"; then
    ALLURE_INPUTS=()
    # Allure only scans its input directory directly. Each copied worker puts
    # results in allure-results/<version>/, so pass those leaf directories.
    while IFS= read -r allure_input; do
      ALLURE_INPUTS+=("$allure_input")
    done < <(find "$RUN_DIR/workers" -type f -name '*-result.json' \
      -exec dirname {} \; | sort -u)
    if [ ${#ALLURE_INPUTS[@]} -eq 0 ]; then
      ALLURE_INPUTS=("$ALLURE_RESULTS_DIR")
    fi
  fi
  if ! npx -y allure@3 generate "${ALLURE_INPUTS[@]}" \
    --config "$ALLURE_CONFIG" \
    -o "$ALLURE_REPORT_DIR"; then
    echo "error: Allure report generation failed" >&2
    echo "--> Raw Allure results: $ALLURE_RESULTS_DIR" >&2
    exit 1
  fi
  echo "--> Allure report: $ALLURE_REPORT_DIR/index.html"
else
  echo "--> Raw Allure results: $ALLURE_RESULTS_DIR"
fi

if [ "$OVERALL_EXIT" -ne 0 ]; then
  echo
  echo "========================================"
  echo " Failed version logs"
  echo "========================================"
  for version in "${VERSIONS[@]}"; do
    if [[ "$(cat "$STATUS_DIR/$version" 2>/dev/null || echo FAIL)" != PASS ]]; then
      echo "--- BEGIN $version ---"
      cat "$LOG_DIR/$version.log" 2>/dev/null || true
      echo "--- END $version ---"
    fi
  done
fi

exit "$OVERALL_EXIT"
