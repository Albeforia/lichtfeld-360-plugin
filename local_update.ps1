# install.ps1
# Copies the lichtfeld-360-plugin source tree into the Lichtfeld plugin directory.
# Run from the project root (where this script lives), or it auto-detects its own location.

$ErrorActionPreference = "Stop"

# --- Paths -----------------------------------------------------------------
# Source = folder containing this script.
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Destination plugin directory.
$DestDir = "$env:USERPROFILE\.lichtfeld\plugins\lichtfeld-360-plugin"

# --- Items to exclude (relative names) ------------------------------------
$ExcludeDirs = @(
    '.git',
    '.venv',
    '__pycache__',
    '.pytest_cache',
    'tmp',
    'dev',
    'docs',
    'tests',
    '.tmp-dll',
    '.superpowers',
    '.claude',
    '.codebuddy'
)
$ExcludeFiles = @(
    'local_update.ps1',          # don't ship the installer into the plugin dir
    # 'uv.lock',              # optional: keep out of deployed plugin
    '*.code-workspace',
    'CLAUDE.md',
    'HANDOVER.md',
    'AGENTS.md',
    'DIAGNOSTICS.md'
)
# Glob pattern exclusions handled separately.
$ExcludeExts = @('.pyc')

# --- Helpers ---------------------------------------------------------------
function Should-Skip($item, $sourceRoot) {
    $name = $item.Name

    # Exclude if the item itself is an excluded dir/file/ext.
    if ($item.PSIsContainer) {
        if ($ExcludeDirs -contains $name) { return $true }
    } else {
        if ($ExcludeFiles -contains $name) { return $true }
        foreach ($ext in $ExcludeExts) {
            if ($name -like "*$ext") { return $true }
        }
    }

    # Exclude if any ancestor directory is an excluded dir (e.g. files inside .git).
    $rel = $item.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
    $segments = $rel -split '[\\/]'
    foreach ($seg in $segments) {
        if ($ExcludeDirs -contains $seg) { return $true }
    }
    return $false
}

# --- Main copy -------------------------------------------------------------
Write-Host "Source : $SourceDir"
Write-Host "Dest   : $DestDir"

if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory not found: $SourceDir"
    exit 1
}

# Create destination (and parent plugins dir) if missing.
$null = New-Item -ItemType Directory -Force -Path $DestDir

$copied = 0
$skipped = 0

# Walk the source tree and copy each allowed item, mirroring structure.
Get-ChildItem -Path $SourceDir -Recurse | ForEach-Object {
    if (Should-Skip $_ $SourceDir) { $script:skipped++; return }

    # Compute the relative path from source root.
    $rel = $_.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
    $target = Join-Path $DestDir $rel

    if ($_.PSIsContainer) {
        $null = New-Item -ItemType Directory -Force -Path $target
    } else {
        $targetDir = Split-Path -Parent $target
        $null = New-Item -ItemType Directory -Force -Path $targetDir
        Copy-Item -Path $_.FullName -Destination $target -Force
        $script:copied++
    }
}

Write-Host ""
Write-Host "Done. Files copied: $copied  (skipped: $skipped)"
Write-Host "Plugin installed at: $DestDir"
