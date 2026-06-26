# =============================================================================
# CD - syntax-check the merged WFL files on the MCP.
#   1. generate a syntax-check WFL (structure based on syntaxcheck.wfl_m) with
#      one START .. SYNTAX block per changed WFL file
#   2. mcpcopy the WFL to  Z:\INSTALLWFL\SYNTAX<PR>   (same params as deploy)
#   3. start it on the MCP through the WFLX named pipe
# Runs on the master build, AFTER deploy.ps1 has copied the source files.
#
# Note: the INITIALIZE / START / IF .. COMPILEDOK .. DISPLAY block is emitted
# per file (inside the loop) rather than once, so each WFL is syntax-checked
# independently when several change in one merge.
# =============================================================================
$ErrorActionPreference = 'Stop'

# --- which changed files are WFL? -------------------------------------------
$wflExt = '(?i)\.(wfl_m)$'
if (-not (Test-Path 'changed_files.txt')) {
    Write-Host "changed_files.txt not found - nothing to syntax-check."; exit 0
}
$wfls = Get-Content 'changed_files.txt' | Where-Object { $_ -match $wflExt }
if (-not $wfls) { Write-Host "No WFL files in this merge - nothing to syntax-check."; exit 0 }

# --- pull request number ----------------------------------------------------
# On the master build CHANGE_ID is not set, so fall back to the PR number in
# the merge commit message ("... #42 ..."), then to the build number.
$pr = $env:CHANGE_ID
if (-not $pr) {
    $msg = (& git log -1 --pretty=%B HEAD) -join "`n"
    if ($msg -match '#(\d+)') { $pr = $Matches[1] }
}
if (-not $pr) { $pr = $env:BUILD_NUMBER }
Write-Host "Pull request number: $pr"

# --- build the syntax-check WFL ---------------------------------------------
$wfl = New-Object System.Collections.Generic.List[string]
$wfl.Add('BEGIN JOB SYNTAX-CHECK;')
$wfl.Add('')
$wfl.Add('TASK T1;')
$wfl.Add('')

foreach ($raw in $wfls) {
    $f = $raw.Trim(); if (-not $f) { continue }

    # name with Z:/ stripped, no extension  (e.g. WFL/GENERAL/HELLOWORLD)
    $name  = $f    -replace '^[^/]+/', 'Z:/'      # project root -> Z:/
    $name  = $name -replace '\.[^./]+$', ''       # strip the extension
    $title = $name -replace '^Z:/', ''            # name excluding Z:/

    $wfl.Add('INITIALIZE(T1);')
    $wfl.Add('')
    $wfl.Add("START $title ON DISK[T1] SYNTAX;")
    $wfl.Add('IF T1 IS COMPILEDOK THEN')
    $wfl.Add("    DISPLAY ""$title, SYNTAX CHECK SUCCESS"";")
    $wfl.Add('ELSE')
    $wfl.Add("    DISPLAY ""$title, SYNTAX CHECK FAILED"";")
    $wfl.Add('')
}
$wfl.Add('END JOB;')

$local = "syntaxcheck_$pr.wfl_m"
Set-Content -LiteralPath $local -Value $wfl -Encoding ASCII
Write-Host "Generated $local ($($wfls.Count) WFL block(s)):"
Get-Content $local | ForEach-Object { Write-Host "    $_" }

# --- copy the WFL to the MCP (same mcpcopy params as deploy) -----------------
$source = (Resolve-Path -LiteralPath $local).Path
$dest   = "Z:\INSTALLWFL\SYNTAX$pr"
Write-Host "mcpcopy.exe `"$source`" `"$dest`" /Z:SR /Y"
& mcpcopy.exe $source $dest /Z:SR /Y
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: mcpcopy of syntax-check WFL failed ($LASTEXITCODE)."; exit 1 }

# --- start the WFL on the MCP via the WFLX named pipe ------------------------
$pipe = "\\192.168.16.5\PIPE\WFLX\T10MR\INSTALLWFL/SYNTAX$pr"
Write-Host "Starting syntax-check WFL: MORE < $pipe"
cmd /c "MORE < $pipe"
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: starting syntax-check WFL failed ($LASTEXITCODE)."; exit 1 }

Write-Host "Syntax-check WFL SYNTAX$pr submitted to the MCP."
