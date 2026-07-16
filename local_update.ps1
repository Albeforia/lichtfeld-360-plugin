# local_update.ps1
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

# Directories that must NEVER be touched in the destination.
$KeepDirs = @('.venv', 'local-wheels')
# Files that must NEVER be deleted from the destination even if they are not in
# the source tree (e.g. a runtime-generated user settings.json).
$KeepFiles = @('settings.json')

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
    $rel = Get-RelPath $item.FullName $sourceRoot
    $segments = $rel -split '/'
    foreach ($seg in $segments) {
        if ($ExcludeDirs -contains $seg) { return $true }
    }
    return $false
}

# Normalize a path to a forward-slash relative path from a root.
function Get-RelPath($path, $root) {
    ($path.Substring($root.Length).TrimStart('\', '/')) -replace '\\', '/'
}

# --- Main ------------------------------------------------------------------
Write-Host "Source : $SourceDir"
Write-Host "Dest   : $DestDir"

if (-not (Test-Path $SourceDir)) {
    Write-Error "Source directory not found: $SourceDir"
    exit 1
}

# Create destination (and parent plugins dir) if missing.
$null = New-Item -ItemType Directory -Force -Path $DestDir

# 1) Build the set of relative paths that SHOULD exist: everything allowed
#    from the source tree. Used both for copying and for orphan removal.
$allowed = New-Object 'System.Collections.Generic.HashSet[string]'
Get-ChildItem -Path $SourceDir -Recurse | ForEach-Object {
    if (Should-Skip $_ $SourceDir) { return }
    $null = $allowed.Add((Get-RelPath $_.FullName $SourceDir))
}

# 2) Remove orphaned items in the destination that no longer exist in the
#    source. Protected directories (e.g. .venv) and their contents are left
#    untouched so we never delete a virtual environment by accident.
#    Items are processed deepest-first so a removed parent is still valid.
if (Test-Path $DestDir) {
    Get-ChildItem -Path $DestDir -Recurse |
        Sort-Object -Property FullName -Descending |
        ForEach-Object {
            $rel = Get-RelPath $_.FullName $DestDir
            $segments = $rel -split '/'
            foreach ($seg in $segments) {
                if ($KeepDirs -contains $seg) { return }   # protected: skip entirely
            }
            if ($KeepFiles -contains $_.Name) { return }   # protected file: keep
            if ($allowed.Contains($rel)) { return }        # still present in source
            Write-Host "Removing orphan: $rel"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
}

# 3) Copy the source tree into the destination, mirroring structure.
#    Copying first (rather than wiping first) means a failure here leaves the
#    previous, working install intact instead of a half-deleted plugin.
$copied = 0
$skipped = 0
Get-ChildItem -Path $SourceDir -Recurse | ForEach-Object {
    if (Should-Skip $_ $SourceDir) { $script:skipped++; return }

    # Compute the relative path from source root.
    $rel = Get-RelPath $_.FullName $SourceDir
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
