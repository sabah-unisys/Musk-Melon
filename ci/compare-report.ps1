# =============================================================================
# Compares each changed MCP file in the PR against the copy currently on Z:.
#
# For every line in changed_files.txt:
#   1. source on Z:  =  the line with 'Musk-Melon/' replaced by 'Z:/'
#   2. mcpcopy.exe copies that source into a temp folder
#   3. diff the Z: copy (current) against the workspace file (the PR version)
#
# Produces (same styling as ci/diff-report.sh):
#   pr_<CHANGE_ID>_z_diff_report.html
#   pr_<CHANGE_ID>_z_changes.txt
#
# Assumes the entries in changed_files.txt begin with 'Musk-Melon/'.
# Run from the workspace root, after the Z: drive has been mapped.
# =============================================================================
$ErrorActionPreference = 'Stop'

$changeId = $env:CHANGE_ID
$listFile = 'changed_files.txt'
$report   = "pr_${changeId}_z_diff_report.html"
$changes  = "pr_${changeId}_z_changes.txt"

# ---- 1. temp folder --------------------------------------------------------
$tmp = Join-Path $env:TEMP ("mcp_z_{0}_{1}" -f $changeId, $env:BUILD_NUMBER)
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Write-Host "Temp folder: $tmp"

function Esc([string]$s) {
    if ($null -eq $s) { return "" }
    return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}

# ---- HTML header (identical CSS to the PR diff report) ---------------------
$head = @"
<!doctype html><html><head><meta charset="utf-8"><title>MCP PR #$changeId vs Z:</title>
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
<h1>MCP changes vs Z: &mdash; Pull Request #$changeId</h1>
<div class="sub">workspace (PR) compared against the current files on Z:</div>
"@
Set-Content -LiteralPath $report  -Value $head -Encoding UTF8
Set-Content -LiteralPath $changes -Value ""    -Encoding UTF8

if (-not (Test-Path $listFile) -or ((Get-Content $listFile | Where-Object { $_.Trim() }).Count -eq 0)) {
    Add-Content $report  '<div class="empty">No MCP files changed in this pull request.</div></body></html>'
    Add-Content $changes 'No MCP files changed in this pull request.'
    Write-Host "Nothing to compare."
    exit 0
}

foreach ($raw in Get-Content $listFile) {
    $f = $raw.Trim()
    if (-not $f) { continue }

    # source on the mapped drive (honours the literal 'Musk-Melon/' -> 'Z:/' rule)
    $src    = $f -replace '^Musk-Melon/', 'Z:/'
    $leaf   = ($src -split '[\\/]')[-1]
    $copied = Join-Path $tmp $leaf
    $wsFile = $f                                   # PR version, in the workspace

    # ---- 2. copy from Z: with mcpcopy --------------------------------------
    Write-Host "mcpcopy.exe `"$src`" `"$tmp`" /Z:RS /C /Q"
    & mcpcopy.exe $src $tmp /Z:RS /C /Q
    $rc = $LASTEXITCODE

    # ---- 3. compare --------------------------------------------------------
    if (-not (Test-Path -LiteralPath $copied)) {
        # not on Z: (or copy failed) -> whole file is new relative to Z:
        Add-Content $report ('<div class="file"><div class="fhead"><span class="pill" style="background:#1a7f37">new on z:</span><span class="fname">' + (Esc $f) + '</span></div><table class="diff"><tbody>')
        Add-Content $changes ""
        Add-Content $changes "##### [NEW vs Z:] $f  (not on Z:, mcpcopy rc=$rc) #####"
        $i = 0
        foreach ($cl in (Get-Content -LiteralPath $wsFile)) {
            $i++
            Add-Content $report ('<tr class="add"><td class="ln"></td><td class="ln">' + $i + '</td><td class="code">+' + (Esc $cl) + '</td></tr>')
            Add-Content $changes ("+" + $cl)
        }
        Add-Content $report '</tbody></table></div>'
        continue
    }

    Add-Content $report ('<div class="file"><div class="fhead"><span class="pill" style="background:#9a6700">modified vs z:</span><span class="fname">' + (Esc $f) + '</span></div><table class="diff"><tbody>')
    Add-Content $changes ""
    Add-Content $changes "##### [MODIFIED vs Z:] $f #####"

    # unified diff: Z: copy = old side, workspace = new side
    $diff = & git --no-pager diff --no-index --no-color -- "$copied" "$wsFile" 2>$null

    $inbody = $false; $oldn = 0; $newn = 0
    foreach ($dl in $diff) {
        if ($dl -match '^@@') {
            $inbody = $true
            if ($dl -match '-(\d+)') { $oldn = [int]$Matches[1] }
            if ($dl -match '\+(\d+)') { $newn = [int]$Matches[1] }
            Add-Content $report ('<tr class="hunk"><td class="ln"></td><td class="ln"></td><td class="code">' + (Esc $dl) + '</td></tr>')
            Add-Content $changes $dl
            continue
        }
        if (-not $inbody) { continue }
        if ($dl.StartsWith('\')) { continue }
        if ($dl.StartsWith('+')) {
            Add-Content $report ('<tr class="add"><td class="ln"></td><td class="ln">' + $newn + '</td><td class="code">' + (Esc $dl) + '</td></tr>')
            $newn++; Add-Content $changes $dl
        } elseif ($dl.StartsWith('-')) {
            Add-Content $report ('<tr class="del"><td class="ln">' + $oldn + '</td><td class="ln"></td><td class="code">' + (Esc $dl) + '</td></tr>')
            $oldn++; Add-Content $changes $dl
        } else {
            Add-Content $report ('<tr><td class="ln">' + $oldn + '</td><td class="ln">' + $newn + '</td><td class="code">' + (Esc $dl) + '</td></tr>')
            $oldn++; $newn++; Add-Content $changes $dl
        }
    }
    Add-Content $report '</tbody></table></div>'
}

Add-Content $report '</body></html>'
Write-Host "Wrote $report and $changes"
