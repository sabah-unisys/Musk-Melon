# =============================================================================
# CD - deploy merged MCP files to the MCP system (Z:) with mcpcopy.exe.
# Runs on the master branch build, after a pull request is merged.
#
# For each MCP file changed by the merge:
#   source      = the file from GitHub (the checked-out workspace file, WITH ext)
#   destination = top-level project folder swapped for Z:, forward slashes ->
#                 backslashes, extension stripped  (identical to the Z: path
#                 built in compare-report.ps1)
#                 e.g. 'Musk Melon/COBOL/GENERAL/HELLOWORLD.c85_m'
#                       -> source: <workspace>\Musk Melon\COBOL\GENERAL\HELLOWORLD.c85_m
#                       -> dest:   Z:\COBOL\GENERAL\HELLOWORLD
#   copy        = mcpcopy.exe <source> <destination> /U:W /T /Z:SR /C /Y /Q
# =============================================================================
$ErrorActionPreference = 'Stop'

# Tracked MCP extensions (kept in step with MCP_EXTENSIONS in the Jenkinsfile).
$exts = if ($env:MCP_EXTENSIONS) { $env:MCP_EXTENSIONS -split '\s+' }
        else { @('c74_m','c85_m','das_m','dat_m','wfl_m') }
$extPattern = '(?i)\.(' + ($exts -join '|') + ')$'

# Files changed by this merge: HEAD^ = previous master tip, HEAD = merge result.
# Works for a merge commit or a squash-merge (one new commit on master).
$changed = & git --no-pager diff --name-only HEAD^ HEAD |
           Where-Object { $_ -match $extPattern }

Set-Content -LiteralPath 'changed_files.txt' -Value $changed -Encoding UTF8

if (-not $changed) {
    Write-Host "No MCP files in this merge - nothing to deploy."
    Set-Content -LiteralPath 'deployed_files.txt' -Value 'No MCP files to deploy.' -Encoding UTF8
    exit 0
}

$log = @()
$failed = 0

foreach ($raw in $changed) {
    $f = $raw.Trim()
    if (-not $f) { continue }

    # A file removed in the merge cannot be copied - record and skip.
    if (-not (Test-Path -LiteralPath $f)) {
        $log += "SKIP    $f  (removed in merge - not copied)"
        continue
    }

    # source: the GitHub file in the workspace (full path, keeps extension)
    $source = (Resolve-Path -LiteralPath $f).Path

    # destination on Z: (same transform as compare-report.ps1)
    $dest = $f    -replace '^[^/]+/', 'Z:/'    # project root -> Z:/
    $dest = $dest -replace '/', '\'            # forward slashes -> backslashes
    $dest = $dest -replace '\.[^.\\]+$', ''    # strip the file extension

    Write-Host "mcpcopy.exe `"$source`" `"$dest`" /U:W /T /Z:SR /C /Y /Q"
    & mcpcopy.exe $source $dest /U:W /T /Z:SR /C /Y /Q
    $rc = $LASTEXITCODE

    if ($rc -eq 0) {
        $log += "OK      $f  ->  $dest"
    } else {
        $log += "FAIL($rc) $f  ->  $dest"
        $failed++
    }
}

$log | ForEach-Object { Write-Host $_ }
Set-Content -LiteralPath 'deployed_files.txt' -Value $log -Encoding UTF8

if ($failed -gt 0) {
    Write-Host "ERROR: $failed file(s) failed to deploy. See deployed_files.txt."
    exit 1
}
Write-Host "Deployed $($changed.Count) file(s) successfully."
