#!/usr/bin/env zsh
# Prints the nearest release tag (e.g. v2.0.0-beta3) if the working tree is
# identical to it, otherwise nothing. This still matches on main after the
# release PR's merge commit (same tree as the tagged bump commit), but not once
# anything has changed since the release.
#
# Usage: ./scripts/release-tag.sh

tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null) || exit 0
git diff --quiet "$tag" -- && echo "$tag"
exit 0
