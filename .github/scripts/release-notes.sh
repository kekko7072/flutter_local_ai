#!/usr/bin/env bash
# Prints the CHANGELOG.md section for one version, for a GitHub release body.
#
# Usage: release-notes.sh <version> [CHANGELOG.md]
# Matches headings such as "## 0.2.1", "## v0.2.1", "## [0.2.1]" or
# "## 0.2.1 — 2026-10-04", and stops at the next "## " heading.
set -euo pipefail

version=${1:?usage: release-notes.sh <version> [changelog]}
changelog=${2:-CHANGELOG.md}

notes=""
if [[ -f "$changelog" ]]; then
  notes=$(awk -v want="$version" '
    /^## / {
      if (found) exit
      heading = $0
      sub(/^## +\[?v?/, "", heading)
      split(heading, parts, /[] \t]/)
      if (parts[1] == want) { found = 1; next }
    }
    found { print }
  ' "$changelog" | sed -e '/./,$!d')
fi

if [[ -n "${notes//[[:space:]]/}" ]]; then
  printf '%s\n' "$notes"
else
  printf 'Release %s.\n' "$version"
fi
