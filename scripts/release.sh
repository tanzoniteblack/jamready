#!/bin/bash
# Create a new release: bumps pubspec version, generates a changelog via claude,
# commits, tags, and (optionally) pushes to trigger the GitHub Actions release workflow.
#
# Usage: ./scripts/release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

current_pubspec_version() {
  grep '^version:' "$PUBSPEC" | sed 's/version: *//'
}

version_name()  { echo "${1%%+*}"; }
build_number()  { echo "${1##*+}"; }

bump_version() {
  local version="$1" part="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  case "$part" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

# Returns the most recent tag matching the given extended-regex pattern, or empty.
last_tag() {
  git tag -l | sort -rV | grep -E "$1" | head -1 || true
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if ! command -v claude &>/dev/null; then
  echo "error: 'claude' CLI not found — install it to generate changelogs automatically" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree has uncommitted changes — commit or stash first" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Release type
# ---------------------------------------------------------------------------

echo ""
echo "Release type:"
PS3="> "
select CHOICE in "stable" "pre-release (beta/rc)"; do
  case "$REPLY" in
    1) BETA=false; break ;;
    2) BETA=true;  break ;;
  esac
done

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

CURRENT_FULL=$(current_pubspec_version)
CURRENT_NAME=$(version_name "$CURRENT_FULL")
CURRENT_BUILD=$(build_number "$CURRENT_FULL")
NEW_BUILD=$((CURRENT_BUILD + 1))

echo ""
echo "Current version: $CURRENT_NAME (build $CURRENT_BUILD)"
echo "Bump:"
select CHOICE in \
  "patch  → $(bump_version "$CURRENT_NAME" patch)" \
  "minor  → $(bump_version "$CURRENT_NAME" minor)" \
  "major  → $(bump_version "$CURRENT_NAME" major)" \
  "manual"; do
  case "$REPLY" in
    1) NEW_NAME=$(bump_version "$CURRENT_NAME" patch); break ;;
    2) NEW_NAME=$(bump_version "$CURRENT_NAME" minor); break ;;
    3) NEW_NAME=$(bump_version "$CURRENT_NAME" major); break ;;
    4) read -rp "Version (e.g. 1.2.3): " NEW_NAME; break ;;
  esac
done

if $BETA; then
  read -rp "Pre-release suffix (e.g. beta1, rc1): " SUFFIX
  TAG="v${NEW_NAME}-${SUFFIX}"
else
  TAG="v${NEW_NAME}"
fi

NEW_VERSION="${NEW_NAME}+${NEW_BUILD}"

echo ""
echo "  Version : $NEW_VERSION"
echo "  Tag     : $TAG"
echo ""
read -rp "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# Changelog via claude
# ---------------------------------------------------------------------------

if $BETA; then
  # Beta changelog covers commits since the last tag of any kind
  LAST_TAG=$(last_tag '^v[0-9]+\.[0-9]+\.[0-9]+')
else
  # Stable changelog covers commits since the last stable release only
  LAST_TAG=$(last_tag '^v[0-9]+\.[0-9]+\.[0-9]+$')
fi

if [ -n "$LAST_TAG" ]; then
  echo "Generating changelog from $LAST_TAG → HEAD..."
  COMMITS=$(git log "${LAST_TAG}..HEAD" --pretty=format:"- %s")
else
  echo "No previous tag found — generating changelog from full history..."
  COMMITS=$(git log --pretty=format:"- %s")
fi

if [ -z "$COMMITS" ]; then
  CHANGELOG="No changes since last release."
else
  PROMPT="Write a concise, human-readable changelog for $TAG of JamReady, a Roller Derby jam timer app. Use plain markdown. Focus on user-facing changes. Group related items under short headings if it helps. Omit purely internal refactors and test-only changes unless significant. Return only the changelog text — no preamble, no code fences."
  CHANGELOG=$(echo "$COMMITS" | claude -p "$PROMPT")
fi

echo ""
echo "--- Changelog ---"
echo "$CHANGELOG"
echo "-----------------"
echo ""
read -rp "Proceed with this changelog? [Y/n] " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Aborted. Edit and re-run."; exit 0; }

# ---------------------------------------------------------------------------
# Commit and tag
# ---------------------------------------------------------------------------

sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
rm -f "$PUBSPEC.bak"

git add "$PUBSPEC"
git commit -m "Bump version to $TAG"
git tag -a "$TAG" -m "$CHANGELOG"

echo ""
echo "Created commit and annotated tag $TAG."
echo ""
read -rp "Push to origin now? [y/N] " PUSH
if [[ "$PUSH" =~ ^[Yy]$ ]]; then
  git push --atomic origin HEAD "$TAG"
  echo ""
  echo "Pushed. GitHub Actions will build and publish the release."
fi
