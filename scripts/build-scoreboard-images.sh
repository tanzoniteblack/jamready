#!/bin/bash
# Build Docker images for each supported CRG scoreboard release and the
# Seattle Derby Brats' temporary `feature-pbt` fork.
# Run this once before running scoreboard integration tests.
# Each image is tagged crg-scoreboard:<version>.
#
# Usage: ./scripts/build-scoreboard-images.sh [--versions v1,v2,...]
#
# Options:
#   --versions  Comma-separated list of versions to build (default: all).
#               `feature-pbt` builds katpet/scoreboard's feature-pbt branch.
#
# Requires: docker, git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALL_VERSIONS=(
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
  feature-pbt
)

OFFICIAL_SCOREBOARD_REPOSITORY="https://github.com/rollerderby/scoreboard.git"
PBT_SCOREBOARD_REPOSITORY="https://github.com/katpet/scoreboard.git"

VERSIONS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --versions) IFS=',' read -ra VERSIONS <<< "$2"; shift 2 ;;
    *)          echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ ${#VERSIONS[@]} -eq 0 ]; then
  VERSIONS=("${ALL_VERSIONS[@]}")
fi

for VERSION in "${VERSIONS[@]}"; do
  IMAGE="crg-scoreboard:$VERSION"
  REPOSITORY="$OFFICIAL_SCOREBOARD_REPOSITORY"
  BRANCH="$VERSION"

  if [ "$VERSION" = "feature-pbt" ]; then
    REPOSITORY="$PBT_SCOREBOARD_REPOSITORY"
  fi

  if docker image inspect "$IMAGE" &>/dev/null; then
    echo "==> $IMAGE already exists, skipping build"
    continue
  fi

  echo "==> Building $IMAGE"
  docker build \
    --build-arg VERSION="$BRANCH" \
    --build-arg SCOREBOARD_REPOSITORY="$REPOSITORY" \
    --tag "$IMAGE" \
    --file "$SCRIPT_DIR/scoreboard.Dockerfile" \
    "$SCRIPT_DIR"
  echo "==> Built $IMAGE"
done

echo ""
echo "Done. Images available:"
for VERSION in "${VERSIONS[@]}"; do
  echo "  crg-scoreboard:$VERSION"
done
