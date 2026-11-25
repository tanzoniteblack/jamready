#!/usr/bin/env zsh
# Create a new release: bumps pubspec version, generates a changelog via claude,
# commits, tags, and opens a release PR against main. Once you merge the PR
# (with a merge commit), the tag is pushed to trigger the GitHub Actions
# release workflow — the script can wait and do that for you.
#
# Usage: ./scripts/release.sh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
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

# Returns the most recent tag reachable from HEAD matching the given
# extended-regex pattern, or empty. Tags only on other branches (e.g. an
# experimental v2.0.0-jambox) are ignored so they don't skew version bumps
# or the changelog range.
last_tag() {
  git tag -l --merged HEAD | sort -rV | grep -E "$1" | head -1 || true
}

# Given a tag like v1.0.0-rc1, echo the base semver (1.0.0).
prerelease_base() { echo "${${1#v}%%-*}"; }

# Given a tag like v1.0.0-rc1, echo the incremented suffix (rc2), or empty if not parseable.
next_prerelease_suffix() {
  local suffix="${1#*-}"          # rc1
  local prefix="${suffix%%[0-9]*}" # rc
  local num="${suffix##*[^0-9]}"  # 1
  [[ -n "$num" ]] && echo "${prefix}$((num + 1))" || echo ""
}

pick() {
  fzf --height=~10 --layout=reverse --no-multi --prompt="$1: "
}

confirm() {
  local answer
  printf '%s [y/N] ' "$1"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Opens the given text in $VISUAL/$EDITOR and echoes the edited result.
edit_text() {
  local file
  file=$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")
  print -r -- "$1" > "$file"
  ${=VISUAL:-${EDITOR:-vi}} "$file" </dev/tty >/dev/tty
  cat "$file"
  rm -f "$file"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

if ! command -v fzf &>/dev/null; then
  echo "error: fzf not found — install it with: brew install fzf" >&2
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "error: 'claude' CLI not found — install it to generate changelogs automatically" >&2
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "error: 'gh' CLI not found — needed to open the release PR (brew install gh)" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: working tree has uncommitted changes — commit or stash first" >&2
  exit 1
fi

BASE_BRANCH=main
if [[ "$(git branch --show-current)" != "$BASE_BRANCH" ]]; then
  echo "error: run releases from $BASE_BRANCH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Release type
# ---------------------------------------------------------------------------

RELEASE_TYPE=$(printf "stable\npre-release (beta/rc)" | pick "Release type") || { echo "Aborted."; exit 0; }
[[ "$RELEASE_TYPE" == stable ]] && BETA=false || BETA=true

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

CURRENT_FULL=$(current_pubspec_version)
CURRENT_NAME=$(version_name "$CURRENT_FULL")
CURRENT_BUILD=$(build_number "$CURRENT_FULL")
NEW_BUILD=$((CURRENT_BUILD + 1))

# When creating a pre-release, check if the last tag is also a pre-release so we
# can offer "same version, next suffix" (e.g. rc1 → rc2) as the default option.
DEFAULT_SUFFIX=""
LAST_PRERELEASE=""
if $BETA; then
  LAST_PRERELEASE=$(last_tag '^v[0-9]+\.[0-9]+\.[0-9]+-')
fi

if [[ -n "$LAST_PRERELEASE" ]]; then
  PREV_BASE=$(prerelease_base "$LAST_PRERELEASE")
  NEXT_SUFFIX=$(next_prerelease_suffix "$LAST_PRERELEASE")
  # "same" only makes sense when the suffix has a number to increment
  # (rc1 → rc2); for e.g. "beta" it would produce an empty suffix.
  SAME_OPTION=""
  [[ -n "$NEXT_SUFFIX" ]] && SAME_OPTION="same   → v${PREV_BASE}-${NEXT_SUFFIX}\n"
  BUMP_MENU="${SAME_OPTION}patch  →$(bump_version "$PREV_BASE" patch)\nminor  → $(bump_version "$PREV_BASE" minor)\nmajor  → $(bump_version "$PREV_BASE" major)\nmanual"
  BUMP=$(printf "$BUMP_MENU" | pick "Bump ($CURRENT_NAME, build $CURRENT_BUILD)") || { echo "Aborted."; exit 0; }
  case "${BUMP%% *}" in
    same)   NEW_NAME="$PREV_BASE"; DEFAULT_SUFFIX="$NEXT_SUFFIX" ;;
    patch)  NEW_NAME=$(bump_version "$PREV_BASE" patch) ;;
    minor)  NEW_NAME=$(bump_version "$PREV_BASE" minor) ;;
    major)  NEW_NAME=$(bump_version "$PREV_BASE" major) ;;
    manual) read "NEW_NAME?Version (e.g. 1.2.3): " ;;
  esac
else
  BUMP=$(printf \
    "patch  → $(bump_version "$CURRENT_NAME" patch)\nminor  → $(bump_version "$CURRENT_NAME" minor)\nmajor  → $(bump_version "$CURRENT_NAME" major)\nmanual" \
    | pick "Bump ($CURRENT_NAME, build $CURRENT_BUILD)") || { echo "Aborted."; exit 0; }
  case "${BUMP%% *}" in
    patch) NEW_NAME=$(bump_version "$CURRENT_NAME" patch) ;;
    minor) NEW_NAME=$(bump_version "$CURRENT_NAME" minor) ;;
    major) NEW_NAME=$(bump_version "$CURRENT_NAME" major) ;;
    manual) read "NEW_NAME?Version (e.g. 1.2.3): " ;;
  esac
fi

if $BETA; then
  read "SUFFIX?Pre-release suffix${DEFAULT_SUFFIX:+ [$DEFAULT_SUFFIX]}: "
  SUFFIX="${SUFFIX:-$DEFAULT_SUFFIX}"
  TAG="v${NEW_NAME}-${SUFFIX}"
else
  TAG="v${NEW_NAME}"
fi

NEW_VERSION="${NEW_NAME}+${NEW_BUILD}"

echo ""
echo "  Version : $NEW_VERSION"
echo "  Tag     : $TAG"
echo ""
confirm "Continue?" || { echo "Aborted."; exit 0; }

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

while true; do
  echo ""
  echo "--- Changelog ---"
  echo "$CHANGELOG"
  echo "-----------------"
  echo ""
  confirm "Proceed with this changelog?" && break
  CHANGELOG=$(edit_text "$CHANGELOG")
  [[ -n "${CHANGELOG//[[:space:]]/}" ]] || { echo "Changelog is empty. Aborted."; exit 0; }
done

# ---------------------------------------------------------------------------
# Commit and tag
# ---------------------------------------------------------------------------

sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"
rm -f "$PUBSPEC.bak"

git add "$PUBSPEC"
git commit -m "Bump version to $TAG"
# verbatim keeps markdown headings, which the default cleanup strips as comments
git tag -a "$TAG" --cleanup=verbatim -m "$CHANGELOG"

echo ""
echo "Created commit and annotated tag $TAG."
echo ""

# ---------------------------------------------------------------------------
# Release PR and tag push
# ---------------------------------------------------------------------------
# main is protected (changes via PR, required CI), so the bump lands through a
# PR. The tag is pushed only after that PR is merged with a merge commit, so the
# tagged commit is part of main's history.

RELEASE_BRANCH="release/$TAG"
RELEASE_COMMIT=$(git rev-parse HEAD)

print_manual_steps() {
  echo "Next steps:"
  echo "  1. Merge the release PR with \"Create a merge commit\" (not squash/rebase)."
  echo "  2. git push origin $TAG"
  echo "  3. git pull --ff-only origin $BASE_BRANCH"
}

confirm "Push $RELEASE_BRANCH and open a release PR?" || {
  echo ""
  echo "Nothing pushed. To publish later:"
  echo "  git push -u origin HEAD:refs/heads/$RELEASE_BRANCH"
  echo "  gh pr create --base $BASE_BRANCH --head $RELEASE_BRANCH"
  print_manual_steps
  exit 0
}

git push -u origin "HEAD:refs/heads/$RELEASE_BRANCH"

PR_BODY="Version bump for \`$TAG\` (\`pubspec.yaml\` → \`$NEW_VERSION\`), created by \`scripts/release.sh\`.

**Merge with \"Create a merge commit\"** (not squash/rebase) so the tagged commit stays in \`$BASE_BRANCH\`'s history. The annotated tag \`$TAG\` is pushed after merging, which triggers the release workflow.

## Changelog

$CHANGELOG"

PR_URL=$(gh pr create --base "$BASE_BRANCH" --head "$RELEASE_BRANCH" \
  --title "Bump version to $TAG" --body "$PR_BODY")
echo ""
echo "Opened release PR: $PR_URL"
echo ""

if ! confirm "Wait here for the PR to be merged, then push $TAG?"; then
  print_manual_steps
  exit 0
fi

echo "Waiting for $PR_URL to be merged (Ctrl-C to stop; the tag stays local)..."
while true; do
  PR_STATE=$(gh pr view "$PR_URL" --json state -q .state)
  [[ "$PR_STATE" == MERGED ]] && break
  if [[ "$PR_STATE" == CLOSED ]]; then
    echo "PR was closed without merging; tag $TAG was not pushed." >&2
    exit 1
  fi
  sleep 15
done

git fetch -q origin "$BASE_BRANCH"
if ! git merge-base --is-ancestor "$RELEASE_COMMIT" "origin/$BASE_BRANCH"; then
  echo "error: $RELEASE_COMMIT is not in origin/$BASE_BRANCH (squash or rebase merge?)." >&2
  echo "Re-point the tag at the merged commit before pushing:" >&2
  echo "  git tag -f -a $TAG --cleanup=verbatim -m \"\$(git tag -l --format='%(contents)' $TAG)\" <merged-sha>" >&2
  exit 1
fi

git push origin "$TAG"
git pull -q --ff-only origin "$BASE_BRANCH" || true
echo ""
echo "Pushed $TAG. GitHub Actions will build and publish the release."
