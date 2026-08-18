#!/bin/bash
# Run remote_engine_test/ against each scoreboard Docker image sequentially,
# newest version first. Stops on the first failure.
#
# Unlike test-all-scoreboards.sh, this does NOT launch the app or an
# emulator/simulator — it runs plain Dart tests (via `flutter test`) that
# drive lib/services/remote_game_engine.dart directly against each
# dockerized scoreboard server over a real WebSocket connection. This is
# far faster since there's no app UI/build in the loop.
#
# Run build-scoreboard-images.sh first.
#
# Usage: ./scripts/test-remote-engine-scoreboards.sh [options] [-- flutter test args]
#
# Options:
#   --versions     Comma-separated list of versions to test (default: all, newest first)
#   --host         Host address the tests connect to (default: 127.0.0.1)
#   --port         Docker host port for the scoreboard container (default: 8001)
#   --results-dir  Directory to write a machine-readable JSON test report per
#                  version to, via `flutter test --file-reporter` (default:
#                  test-results). Consume with e.g. dorny/test-reporter
#                  (reporter: flutter-json) in CI.
#
# Passes any args after -- directly to flutter test.

set -euo pipefail

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
RESULTS_DIR="test-results"
FLUTTER_ARGS=()

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions)    IFS=',' read -ra VERSIONS <<< "$2"; shift 2 ;;
    --host)        HOST="$2"; shift 2 ;;
    --port)        PORT="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --)            shift; FLUTTER_ARGS=("$@"); break ;;
    *)             echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${ALL_VERSIONS[@]}")
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

CONTAINER="crg-scoreboard-remote-engine-test"

cleanup() {
  docker rm -f "$CONTAINER" &>/dev/null || true
}
trap cleanup EXIT

echo ""
echo "--> Testing ${#VERSIONS[@]} version(s) on $HOST:$PORT"
echo "--> Versions: ${VERSIONS[*]}"

PASS=()

for VERSION in "${VERSIONS[@]}"; do
  IMAGE="crg-scoreboard:$VERSION"

  echo ""
  echo "========================================"
  echo "  $IMAGE  (host: $HOST  port: $PORT)"
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
  REPORT_FILE="$RESULTS_DIR/remote-engine-$VERSION.json"
  EXIT_CODE=0
  flutter test remote_engine_test/ \
    --dart-define=SCOREBOARD_HOST="$HOST" \
    --dart-define=SCOREBOARD_PORT="$PORT" \
    --dart-define=SCOREBOARD_VERSION="$VERSION" \
    --file-reporter="json:$REPORT_FILE" \
    "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" \
    2>&1 | tee "$TEST_LOG" \
    || EXIT_CODE=$?

  docker rm -f "$CONTAINER" &>/dev/null || true

  if [ $EXIT_CODE -eq 0 ]; then
    PASS+=("$VERSION")
    echo "--> PASS: $VERSION (report: $REPORT_FILE)"
    rm -f "$TEST_LOG"
  else
    echo "--> FAIL: $VERSION (exit $EXIT_CODE, report: $REPORT_FILE)"
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
