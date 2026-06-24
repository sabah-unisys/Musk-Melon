#!/usr/bin/env bash
# Prints per-file changes to the build log (visible in the Jenkins UI) and
# saves the same text to pr_<id>_changes.txt.
#   new file      -> entire content
#   modified file -> only the line changes
set -euo pipefail

TARGET="${CHANGE_TARGET:-${DEFAULT_TARGET:-main}}"
BASE="origin/${TARGET}"
REPORT="pr_${CHANGE_ID}_changes.txt"
: > "$REPORT"

if [ ! -s changed_files.txt ]; then
  echo "No MCP files changed in this pull request." | tee -a "$REPORT"
  exit 0
fi

git diff --name-status "${BASE}...HEAD" | while IFS=$'\t' read -r STATUS PATH_A PATH_B; do
  FILE="${PATH_B:-$PATH_A}"
  grep -qxF "$FILE" changed_files.txt || continue
  {
    echo ""
    echo "##################################################################"
    echo "#  [${STATUS}]  ${FILE}"
    echo "##################################################################"
  } | tee -a "$REPORT"
  case "$STATUS" in
    A*)
      echo ">>> NEW FILE - full content:" | tee -a "$REPORT"
      echo "------------------------------------------------------------------" | tee -a "$REPORT"
      git show "HEAD:${FILE}" | tee -a "$REPORT" || echo "(could not read content)" | tee -a "$REPORT" ;;
    D*)
      echo ">>> FILE DELETED" | tee -a "$REPORT" ;;
    *)
      echo ">>> MODIFIED - line changes:" | tee -a "$REPORT"
      echo "------------------------------------------------------------------" | tee -a "$REPORT"
      git diff "${BASE}...HEAD" -- "$FILE" | tee -a "$REPORT" ;;
  esac
done
