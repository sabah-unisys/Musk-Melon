# =============================================================================
# CD - back up the MCP before the deploy overwrites any files.
#   1. generate a backup WFL locally  (backupcopy.wfl_m) with one COPY .. AS ..
#      entry per changed file, each renamed with today's MMDDYY date suffix
#   2. mcpcopy the WFL to  Z:\BACKUPCOPY   (same params as the install-WFL copy:
#      /Z:SR /Y - identical to compile-wfl.ps1 / syntaxcheck-wfl.ps1)
#   3. start it on the MCP through the WFLX named pipe with MORE
# Runs on the master build, BEFORE deploy.ps1 copies the new source files.
#
# File list source:
#   Primary  - changed_files.txt (written by ci/changed-files.sh).
#   Fallback - on the post-merge master build that CI text file may not be
#              present in the workspace, so we derive the same list from the
#              merge commit (git diff --name-only HEAD^ HEAD), exactly like
#              deploy.ps1 does. Either way the backup covers the files the
#              Deploy stage is about to overwrite.
#
# Path transform (per file):
#   strip the leading repo folder segment (e.g. 'Musk Melon/') generically,
#   then drop the extension:
#     Musk Melon/COBOL/GENERAL/ADDTWONUM.c85_m  ->  COBOL/GENERAL/ADDTWONUM
#   and each file is copied AS <name>/<MMDDYY>:
#     COPY COBOL/GENERAL/ADDTWONUM AS COBOL/GENERAL/ADDTWONUM/071326
# =============================================================================
$ErrorActionPreference = 'Stop'

# --- date stamp for the backup copies (MMDDYY, e.g. 071326) -----------------
$date = Get-Date -Format 'MMddyy'

# --- MCP-tracked extensions (used only by the merge-commit fallback) --------
$mcpExtensions = if ($env:MCP_EXTENSIONS) { $env:MCP_EXTENSIONS } else { 'c74_m c85_m das_m dat_m wfl_m' }
$extAlt = ($mcpExtensions -split '\s+' | Where-Object { $_ }) -join '|'

# --- gather the changed files -----------------------------------------------
$changed = @()
if (Test-Path -LiteralPath 'changed_files.txt') {
    $changed = Get-Content -LiteralPath 'changed_files.txt' |
        ForEach-Object { $_.Trim() } |
        Where-Object   { $_ }
    Write-Host "Read $($changed.Count) file(s) from changed_files.txt."
}
if (-not $changed) {
    Write-Host "changed_files.txt not found or empty - deriving from merge commit (HEAD^..HEAD)."
    $changed = & git diff --name-only HEAD^ HEAD |
        ForEach-Object { $_.Trim() } |
        Where-Object   { $_ -and ($_ -imatch "\.($extAlt)$") }
    Write-Host "Derived $($changed.Count) file(s) from the merge commit."
}
if (-not $changed) {
    Write-Host "No changed MCP files found - nothing to back up. Skipping backup WFL."
    exit 0
}

# --- transform each path into an MCP title ----------------------------------
$names = foreach ($f in $changed) {
    $n = $f -replace '\\', '/'          # normalise separators
    $n = $n -replace '^[^/]*/', ''      # strip first path segment (Musk Melon/)
    $n = $n -replace '\.[^./]+$', ''    # strip extension
    $n
}
$names = @($names | Where-Object { $_ })

# --- build the dynamic COPY ... AS .../<date> block -------------------------
# One entry per file; single COPY keyword, comma-separated, then FROM .. TO ..
$copyLines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $names.Count; $i++) {
    $n     = $names[$i]
    $entry = "$n AS $n/$date"
    if ($i -eq 0) { $entry = "COPY $entry" } else { $entry = "     $entry" }
    if ($i -lt ($names.Count - 1)) { $entry += ',' }
    $copyLines.Add($entry)
}

# --- assemble the backup WFL (static shell matches backupcopy.wfl_m) --------
$wfl = New-Object System.Collections.Generic.List[string]
$wfl.Add('BEGIN JOB BACKUP-COPY;')
$wfl.Add('')
$wfl.Add('TASK T1;')
$wfl.Add("% '%' is used to add comment in wfl files")
$wfl.Add('% For each file present in the commit change')
$wfl.Add('')
$wfl.Add('INITIALIZE(T1);')
$wfl.Add('')
foreach ($l in $copyLines) { $wfl.Add($l) }   # <-- dynamic part
$wfl.Add('FROM DISK(PACK) TO DISK(PACK)[T1];')
$wfl.Add('')
$wfl.Add(' IF T1(TASKVALUE)= 0 THEN')
$wfl.Add('  BEGIN')
$wfl.Add('   DISPLAY "ALL (WFL)FILES WERE COPIED";')
$wfl.Add('  END')
$wfl.Add(' ELSE')
$wfl.Add('   DISPLAY "NOT ALL (WFL)FILES WERE COPIED. CHECK JOB SUMMARY";')
$wfl.Add('%')
$wfl.Add('')
$wfl.Add('')
$wfl.Add('')
$wfl.Add('END JOB;')

$local = 'backupcopy.wfl_m'
Set-Content -LiteralPath $local -Value $wfl -Encoding ASCII
Write-Host "Generated $local :"
Get-Content $local | ForEach-Object { Write-Host "    $_" }

# --- copy the WFL to the MCP (same mcpcopy params as the install-WFL copy) ---
$source = (Resolve-Path -LiteralPath $local).Path
$dest   = 'Z:\BACKUPCOPY'
Write-Host "mcpcopy.exe `"$source`" `"$dest`" /Z:SR /Y"
& mcpcopy.exe $source $dest /Z:SR /Y
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: mcpcopy of backup WFL failed ($LASTEXITCODE)."; exit 1 }

# --- start the WFL on the MCP via the WFLX named pipe ------------------------
$pipe = "\\192.168.16.5\PIPE\WFLX\T10MR\BACKUPCOPY"
Write-Host "Starting backup WFL: MORE < $pipe"
cmd /c "MORE < $pipe"
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: starting backup WFL failed ($LASTEXITCODE)."; exit 1 }

Write-Host "Backup WFL BACKUP-COPY submitted to the MCP."
