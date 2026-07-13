# =============================================================================
# CD - back up the MCP before the deploy overwrites any files.
#   1. generate a backup WFL locally  (BACKUPCOPY.wfl_m)
#   2. mcpcopy the WFL to  Z:\BACKUPCOPY   (same params as the install-WFL copy:
#      /Z:SR /Y - identical to compile-wfl.ps1 / syntaxcheck-wfl.ps1)
#   3. start it on the MCP through the WFLX named pipe with MORE
# Runs on the master build, BEFORE deploy.ps1 copies the new source files.
#
# Note: BACKUPCOPY.wfl_m has a fixed name (no <PR> suffix) and does not read
# changed_files.txt, so it can safely run ahead of deploy.ps1 (which is what
# writes changed_files.txt). Adjust the WFL body below to your site's backup.
# =============================================================================
$ErrorActionPreference = 'Stop'

# --- build the backup WFL ---------------------------------------------------
$wfl = New-Object System.Collections.Generic.List[string]
$wfl.Add('BEGIN JOB BACKUPCOPY;')
$wfl.Add('')
$wfl.Add('TASK T1;')
$wfl.Add('')
# ---------------------------------------------------------------------------
# TODO: replace the body below with your real backup logic. This placeholder
# shows the expected shape - a WFL that backs up the MCP files the Deploy
# stage is about to overwrite (e.g. a WFL COPY to a backup pack/directory).
#   e.g.  COPY = & COBOL/= & WFL/= FROM DISK TO BACKUP(PACK);
# ---------------------------------------------------------------------------
$wfl.Add('% --- backup body goes here ---')
$wfl.Add('')
$wfl.Add('END JOB;')

$local = 'BACKUPCOPY.wfl_m'
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

Write-Host "Backup WFL BACKUPCOPY submitted to the MCP."
