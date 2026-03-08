#!/bin/bash
# Build Docker images for each supported CRG scoreboard release.
# Run this once before running scoreboard integration tests.
# Each image is tagged crg-scoreboard:<version>.
#
# Usage: ./scripts/build-scoreboard-images.sh
#
# Requires: docker, git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSIONS=(
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

for VERSION in "${VERSIONS[@]}"; do
  IMAGE="crg-scoreboard:$VERSION"

  if docker image inspect "$IMAGE" &>/dev/null; then
    echo "==> $IMAGE already exists, skipping build"
    continue
  fi

  echo "==> Building $IMAGE"
  docker build \
    --build-arg VERSION="$VERSION" \
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
