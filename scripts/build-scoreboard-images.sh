#!/bin/bash
# Build Docker images for each scoreboard release.
# Run this once before testing. Each image is tagged crg-scoreboard:<version>.
#
# Usage: ./scripts/build-scoreboard-images.sh [path/to/scoreboard/repo]
#
# Requires: docker, ant, java 8+

set -euo pipefail

SCOREBOARD_REPO="${1:-/Users/ryan/Code/opensource/scoreboard}"
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

if [ ! -d "$SCOREBOARD_REPO/.git" ]; then
  echo "error: $SCOREBOARD_REPO is not a git repository" >&2
  exit 1
fi

# Temporary worktree directory — cleaned up on exit
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

for VERSION in "${VERSIONS[@]}"; do
  IMAGE="crg-scoreboard:$VERSION"

  if docker image inspect "$IMAGE" &>/dev/null; then
    echo "==> $IMAGE already exists, skipping build"
    continue
  fi

  echo "==> Building $IMAGE"

  CHECKOUT_DIR="$WORK_DIR/$VERSION"
  git -C "$SCOREBOARD_REPO" worktree add --detach "$CHECKOUT_DIR" "$VERSION" 2>/dev/null \
    || git -C "$SCOREBOARD_REPO" worktree add --force --detach "$CHECKOUT_DIR" "$VERSION"

  # Build the JAR inside the checkout
  (cd "$CHECKOUT_DIR" && ant compile 2>&1)

  # Write a Dockerfile into the checkout and build the image
  cat > "$CHECKOUT_DIR/Dockerfile" <<'DOCKERFILE'
FROM arm64v8/eclipse-temurin:8-jre
WORKDIR /scoreboard
COPY . .
EXPOSE 8000
ENTRYPOINT ["java", \
  "-Done-jar.silent=true", \
  "-Dorg.eclipse.jetty.server.LEVEL=WARN", \
  "-jar", "lib/crg-scoreboard.jar"]
DOCKERFILE

  docker build --tag "$IMAGE" "$CHECKOUT_DIR"

  git -C "$SCOREBOARD_REPO" worktree remove --force "$CHECKOUT_DIR"
  echo "==> Built $IMAGE"
done

echo ""
echo "Done. Images available:"
for VERSION in "${VERSIONS[@]}"; do
  echo "  crg-scoreboard:$VERSION"
done
