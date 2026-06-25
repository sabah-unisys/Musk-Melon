#!/usr/bin/env bash
# Lists the changed MCP files in the current pull request and saves the
# names to changed_files.txt (also echoed to the build log).
set -euo pipefail

TARGET="${CHANGE_TARGET:-${DEFAULT_TARGET:-main}}"
EXT="${MCP_EXTENSIONS:-c74_m c85_m das_m dat_m wfl_m}"

# Ensure the target branch is available locally to diff against (no webhook needed).
# Non-fatal: the GitHub Branch Source has usually fetched it already.
git fetch --no-tags origin "+refs/heads/${TARGET}:refs/remotes/origin/${TARGET}" \
  || echo "warning: could not fetch ${TARGET}; using the ref already in the workspace"

# Build a case-insensitive extension pattern, e.g. \.(c74_m|c85_m|das_m|dat_m)$
PATTERN="\.($(echo "$EXT" | tr ' ' '|'))$"

git diff --name-only "origin/${TARGET}...HEAD" \
  | grep -iE "$PATTERN" \
  | sort -u > changed_files.txt || true

echo "=================================================================="
echo " PR #${CHANGE_ID}: ${CHANGE_BRANCH:-?} -> ${TARGET}"
echo "=================================================================="
echo "Changed MCP files:"
if [ -s changed_files.txt ]; then cat changed_files.txt; else echo "(none)"; fi
