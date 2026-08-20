#!/bin/bash
# Run both CRG scoreboard compatibility suites and merge their local Allure
# results into one version-first report.
#
# Usage: ./scripts/test-scoreboards.sh [options] [-- flutter test args]
#
# Options:
#   --versions       Comma-separated scoreboard versions (default: all)
#   --jobs           Maximum concurrent headless engine workers (default: 1)
#   --emulator-jobs  Maximum emulator workers (default: all running emulators)
#   --results-dir    Parent directory for the combined report (default: test-results)
#   --no-html        Leave raw Allure result files without generating HTML

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scoreboard-test-runner.sh"

VERSIONS=""
ENGINE_JOBS=1
EMULATOR_JOBS=""
RESULTS_DIR="test-results"
GENERATE_HTML=true
FLUTTER_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions) VERSIONS="$2"; shift 2 ;;
    --jobs) ENGINE_JOBS="$2"; shift 2 ;;
    --emulator-jobs) EMULATOR_JOBS="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --no-html) GENERATE_HTML=false; shift ;;
    --) shift; FLUTTER_ARGS=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

scoreboard_require_positive_integer --jobs "$ENGINE_JOBS" || exit 1
if [[ -n "$EMULATOR_JOBS" ]]; then
  scoreboard_require_positive_integer --emulator-jobs "$EMULATOR_JOBS" || exit 1
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="$RESULTS_DIR/scoreboards-$RUN_ID"
mkdir -p "$RUN_DIR"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
ENGINE_RESULTS_DIR="$RUN_DIR/remote-engine"
EMULATOR_RESULTS_DIR="$RUN_DIR/emulator-integration"
ALLURE_REPORT_DIR="$RUN_DIR/allure-report"

COMMON_ARGS=()
if [[ -n "$VERSIONS" ]]; then
  COMMON_ARGS+=(--versions "$VERSIONS")
fi

echo "--> Combined scoreboard compatibility run: $RUN_DIR"
echo "--> Headless engine workers: $ENGINE_JOBS"
if [[ -n "$EMULATOR_JOBS" ]]; then
  echo "--> Emulator worker cap: $EMULATOR_JOBS"
else
  echo "--> Emulator worker cap: available emulators"
fi

ENGINE_EXIT=0
echo ""
echo "========================================"
echo " Headless remote-engine suite"
echo "========================================"
"$SCRIPT_DIR/test-remote-engine-scoreboards.sh" \
  "${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}" \
  --jobs "$ENGINE_JOBS" \
  --results-dir "$ENGINE_RESULTS_DIR" \
  --no-html \
  -- "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" || ENGINE_EXIT=$?

EMULATOR_EXIT=0
echo ""
echo "========================================"
echo " Emulator integration suite"
echo "========================================"
EMULATOR_ARGS=()
if [[ -n "$EMULATOR_JOBS" ]]; then
  EMULATOR_ARGS+=(--jobs "$EMULATOR_JOBS")
fi
"$SCRIPT_DIR/test-all-scoreboards.sh" \
  "${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"}" \
  "${EMULATOR_ARGS[@]+"${EMULATOR_ARGS[@]}"}" \
  --results-dir "$EMULATOR_RESULTS_DIR" \
  --no-html \
  -- "${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}" || EMULATOR_EXIT=$?

OVERALL_EXIT=0
if [ "$ENGINE_EXIT" -ne 0 ] || [ "$EMULATOR_EXIT" -ne 0 ]; then
  OVERALL_EXIT=1
fi

if "$GENERATE_HTML"; then
  ALLURE_INPUTS=()
  while IFS= read -r allure_input; do
    ALLURE_INPUTS+=("$allure_input")
  done < <(find "$RUN_DIR" -type f -name '*-result.json' -exec dirname {} \; | sort -u)
  echo ""
  echo "--> Generating combined Allure HTML report"
  if scoreboard_generate_allure_report "$ALLURE_REPORT_DIR" "${ALLURE_INPUTS[@]+"${ALLURE_INPUTS[@]}"}"; then
    echo "--> Allure report: $ALLURE_REPORT_DIR/index.html"
  else
    echo "--> Raw Allure results: $RUN_DIR" >&2
    OVERALL_EXIT=1
  fi
else
  echo "--> Raw Allure results: $RUN_DIR"
fi

exit "$OVERALL_EXIT"
