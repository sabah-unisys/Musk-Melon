# =============================================================================
# CD - compile the merged COBOL files on the MCP.
#   1. generate a compile WFL (structure based on compile_SET.wfl_m) with one
#      COMPILE block per changed COBOL file
#   2. mcpcopy the WFL to  Z:\INSTALLWFL\COMPILE<PR>   (same params as deploy)
#   3. start it on the MCP through the WFLX named pipe
# Runs on the master build, AFTER deploy.ps1 has copied the source files.
#
# Note: the IF .. COMPILEDOK .. SECURITY check is emitted per file (inside the
# loop) rather than once at the end, so each COBOL file is compiled and secured
# independently when several change in one merge.
# =============================================================================
$ErrorActionPreference = 'Stop'

# --- which changed files are COBOL? -----------------------------------------
$cobolExt = '(?i)\.(c74_m|c85_m)$'
if (-not (Test-Path 'changed_files.txt')) {
    Write-Host "changed_files.txt not found - nothing to compile."; exit 0
}
$cobol = Get-Content 'changed_files.txt' | Where-Object { $_ -match $cobolExt }
if (-not $cobol) { Write-Host "No COBOL files in this merge - nothing to compile."; exit 0 }

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

# --- build the compile WFL --------------------------------------------------
function Get-Compiler([string]$path) {
    if ($path -match '(?i)\.c74_m$') { 'COBOL74' } else { 'COBOL85' }
}

$wfl = New-Object System.Collections.Generic.List[string]
$wfl.Add('BEGIN JOB COMPILE-JOB;')
$wfl.Add('')
$wfl.Add('TASK T1;')
$wfl.Add('')

foreach ($raw in $cobol) {
    $f = $raw.Trim(); if (-not $f) { continue }
    $comp = Get-Compiler $f

    # name in Z:/ forward-slash form, no extension  (e.g. Z:/COBOL/GENERAL/HELLOWORLD)
    $name   = $f    -replace '^[^/]+/', 'Z:/'      # project root -> Z:/
    $name   = $name -replace '\.[^./]+$', ''       # strip the extension
    $object = $name -replace '^Z:/COBOL/', 'OBJECT/'   # COMPILE target
    $title  = $name -replace '^Z:/', ''                # source TITLE on disk

    $wfl.Add('INITIALIZE (T1);')
    $wfl.Add("COMPILE $object")
    $wfl.Add(" WITH $comp [T1] LIBRARY;")
    $wfl.Add('COMPILER FILE SOURCE (KIND = DISK,')
    $wfl.Add("TITLE = $title ON DISK);")
    $wfl.Add('    COMPILER DATA CARD')
    $wfl.Add('000000$SET MERGE FREE ERRLIST')
    $wfl.Add('?')
    $wfl.Add('IF T1 IS COMPILEDOK THEN')
    $wfl.Add("SECURITY $object PUBLIC IO")
    $wfl.Add('ELSE')
    $wfl.Add("DISPLAY ""COMPILATION FAILED FOR $object"";")
    $wfl.Add('')
}
$wfl.Add('END JOB;')

$local = "compile_$pr.wfl_m"
Set-Content -LiteralPath $local -Value $wfl -Encoding ASCII
Write-Host "Generated $local ($($cobol.Count) COBOL block(s)):"
Get-Content $local | ForEach-Object { Write-Host "    $_" }

# --- copy the WFL to the MCP (same mcpcopy params as deploy) -----------------
$source = (Resolve-Path -LiteralPath $local).Path
$dest   = "Z:\INSTALLWFL\COMPILE$pr"
# Write-Host "mcpcopy.exe `"$source`" `"$dest`" /U:W /T /Z:SR /C /Y /Q"
# & mcpcopy.exe $source $dest /U:W /T /Z:SR /C /Y /Q
Write-Host "mcpcopy.exe `"$source`" `"$dest`" /Z:SR /Y"
& mcpcopy.exe $source $dest /Z:SR /Y
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: mcpcopy of compile WFL failed ($LASTEXITCODE)."; exit 1 }

# --- start the WFL on the MCP via the WFLX named pipe ------------------------
$pipe = "\\192.168.16.5\PIPE\WFLX\INSTALLWFL/COMPILE$pr"
Write-Host "Starting compile WFL: MORE < $pipe"
cmd /c "MORE < $pipe"
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: starting compile WFL failed ($LASTEXITCODE)."; exit 1 }

Write-Host "Compile WFL COMPILE$pr submitted to the MCP."
