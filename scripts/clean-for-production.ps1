<#
.SYNOPSIS
    Clean up 9Router project for production ARM64 build.
.DESCRIPTION
    Removes directories and files not needed for the containerized production build.
    Safe to run multiple times (idempotent). Does NOT touch production/, custom/, scripts/, src/, open-sse/.
.PARAMETER Confirm
    If set, actually deletes files. Without it, runs in dry-run mode.
.EXAMPLE
    .\scripts\clean-for-production.ps1
    .\scripts\clean-for-production.ps1 -Confirm
#>
param(
    [switch]$Confirm
)

$ErrorActionPreference = "Continue"
$root = $PSScriptRoot | Split-Path -Parent

# Directories to remove
$dirsToRemove = @(
    "tests",
    "cli",
    "docs",
    "gitbook",
    "i18n",
    ".github",
    ".vscode",
    "skills"
)

# Root files to remove
$filesToRemove = @(
    "Dockerfile",
    "docker-compose.yml",
    "DOCKER.md",
    "DEPLOYMENT_GUIDE.md",
    "captain-definition",
    "start.sh",
    ".env.production"
)

$removedDirs = @()
$removedFiles = @()
$skipped = @()

Write-Host "=== 9Router Production Cleanup ===" -ForegroundColor Cyan
Write-Host ""

if (-not $Confirm) {
    Write-Host "[DRY-RUN] No files will be deleted. Add -Confirm to execute." -ForegroundColor Yellow
    Write-Host ""
}

# Remove directories
Write-Host "--- Directories ---" -ForegroundColor Green
foreach ($dir in $dirsToRemove) {
    $path = Join-Path $root $dir
    if (Test-Path $path) {
        $size = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        if ($Confirm) {
            Remove-Item $path -Recurse -Force
            $removedDirs += [PSCustomObject]@{Name=$dir; SizeMB=$sizeMB}
        } else {
            Write-Host "  [WILL REMOVE] $dir/  ($sizeMB MB)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [SKIP] $dir/ (not found)" -ForegroundColor Gray
        $skipped += $dir
    }
}

Write-Host ""

# Remove root files
Write-Host "--- Root Files ---" -ForegroundColor Green
foreach ($file in $filesToRemove) {
    $path = Join-Path $root $file
    if (Test-Path $path) {
        $sizeKB = [math]::Round((Get-Item $path).Length / 1KB, 1)
        if ($Confirm) {
            Remove-Item $path -Force
            $removedFiles += [PSCustomObject]@{Name=$file; SizeKB=$sizeKB}
        } else {
            Write-Host "  [WILL REMOVE] $file  ($sizeKB KB)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [SKIP] $file (not found)" -ForegroundColor Gray
        $skipped += $file
    }
}

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
if ($removedDirs.Count -gt 0) {
    Write-Host "Directories removed:" -ForegroundColor Green
    $removedDirs | ForEach-Object { Write-Host "  - $($_.Name)/ ($($_.SizeMB) MB)" }
}
if ($removedFiles.Count -gt 0) {
    Write-Host "Files removed:" -ForegroundColor Green
    $removedFiles | ForEach-Object { Write-Host "  - $($_.Name) ($($_.SizeKB) KB)" }
}
$totalSaved = ($removedDirs | ForEach-Object { [double]$_.SizeMB } | Measure-Object -Sum).Sum +
              ($removedFiles | ForEach-Object { [double]$_.SizeKB / 1024 } | Measure-Object -Sum).Sum
Write-Host "Total space saved: ~$([math]::Round($totalSaved, 2)) MB" -ForegroundColor Green
if ($skipped.Count -gt 0) {
    Write-Host "Skipped (not present): $($skipped -join ', ')" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Cleanup Complete ===" -ForegroundColor Cyan
