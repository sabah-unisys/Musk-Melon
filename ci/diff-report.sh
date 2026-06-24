#!/usr/bin/env bash
# Generates an HTML diff report for the changed MCP files in a pull request.
# Reads changed_files.txt (produced by changed-files.sh) from the current dir.
# Writes the HTML page to stdout.  Pure bash + awk, no Python required.
set -euo pipefail

TARGET="${CHANGE_TARGET:-${DEFAULT_TARGET:-main}}"
BASE="origin/${TARGET}"

esc_attr() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

pill() {
  case "$1" in
    A*) echo 'new #1a7f37' ;;
    M*) echo 'modified #9a6700' ;;
    D*) echo 'deleted #cf222e' ;;
    R*) echo 'renamed #0969da' ;;
    *)  echo "$1 #57606a" ;;
  esac
}

cat <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>MCP PR #${CHANGE_ID} diff</title>
<style>
body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:24px;color:#1f2328;background:#fff}
h1{font-size:18px;margin:0 0 4px} .sub{color:#57606a;font-size:13px;margin-bottom:20px}
.file{border:1px solid #d0d7de;border-radius:8px;margin-bottom:18px;overflow:hidden}
.fhead{background:#f6f8fa;padding:8px 12px;border-bottom:1px solid #d0d7de;display:flex;align-items:center;gap:10px}
.pill{color:#fff;font-size:11px;font-weight:600;padding:2px 8px;border-radius:20px;text-transform:uppercase;letter-spacing:.3px}
.fname{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:13px}
table.diff{border-collapse:collapse;width:100%;font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12.5px}
td.ln{min-width:40px;text-align:right;padding:0 10px;color:#8c959f;background:#f6f8fa;border-right:1px solid #eaeef2;white-space:nowrap}
td.code{padding:0 12px;white-space:pre-wrap;word-break:break-word}
tr.add td.code{background:#e6ffec} tr.add td.ln{background:#cdffd8}
tr.del td.code{background:#ffebe9} tr.del td.ln{background:#ffd7d5}
tr.hunk td.code{background:#ddf4ff;color:#0550ae} tr.hunk td.ln{background:#ddf4ff}
.empty{padding:16px;color:#57606a}
</style></head><body>
<h1>MCP changes &mdash; Pull Request #${CHANGE_ID}</h1>
<div class="sub">$(esc_attr "${CHANGE_BRANCH:-?}") &rarr; $(esc_attr "${TARGET}")</div>
HTML

if [ ! -s changed_files.txt ]; then
  echo '<div class="empty">No MCP files changed in this pull request.</div>'
  echo '</body></html>'
  exit 0
fi

STATUS_TABLE="$(git diff --name-status "${BASE}...HEAD")"

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  ST="$(printf '%s\n' "$STATUS_TABLE" | awk -F'\t' -v f="$FILE" '$NF==f{print $1; exit}')"
  [ -n "$ST" ] || ST="M"
  read -r LABEL COLOR <<<"$(pill "$ST")"

  printf '<div class="file"><div class="fhead"><span class="pill" style="background:%s">%s</span><span class="fname">%s</span></div>' \
    "$COLOR" "$LABEL" "$(esc_attr "$FILE")"

  case "$ST" in
    D*)
      echo '<div class="empty">File deleted.</div></div>'
      ;;
    A*)
      echo '<table class="diff"><tbody>'
      { git show "HEAD:${FILE}" 2>/dev/null || true; } | awk '
        function esc(s){gsub(/&/,"\\&amp;",s);gsub(/</,"\\&lt;",s);gsub(/>/,"\\&gt;",s);return s}
        {print "<tr class=\"add\"><td class=\"ln\"></td><td class=\"ln\">" NR "</td><td class=\"code\">+" esc($0) "</td></tr>"}'
      echo '</tbody></table></div>'
      ;;
    *)
      echo '<table class="diff"><tbody>'
      { git diff "${BASE}...HEAD" -- "$FILE" || true; } | awk '
        function esc(s){gsub(/&/,"\\&amp;",s);gsub(/</,"\\&lt;",s);gsub(/>/,"\\&gt;",s);return s}
        /^@@/ {
          inbody=1
          if (match($0,/-[0-9]+/)) oldn=substr($0,RSTART+1,RLENGTH-1)+0
          if (match($0,/\+[0-9]+/)) newn=substr($0,RSTART+1,RLENGTH-1)+0
          print "<tr class=\"hunk\"><td class=\"ln\"></td><td class=\"ln\"></td><td class=\"code\">" esc($0) "</td></tr>"
          next
        }
        inbody==0 {next}
        /^\\/ {next}
        /^\+/ {print "<tr class=\"add\"><td class=\"ln\"></td><td class=\"ln\">" newn "</td><td class=\"code\">" esc($0) "</td></tr>"; newn++; next}
        /^-/  {print "<tr class=\"del\"><td class=\"ln\">" oldn "</td><td class=\"ln\"></td><td class=\"code\">" esc($0) "</td></tr>"; oldn++; next}
        {print "<tr><td class=\"ln\">" oldn "</td><td class=\"ln\">" newn "</td><td class=\"code\">" esc($0) "</td></tr>"; oldn++; newn++}'
      echo '</tbody></table></div>'
      ;;
  esac
done < changed_files.txt

echo '</body></html>'
