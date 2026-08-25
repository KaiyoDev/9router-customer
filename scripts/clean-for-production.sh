#!/usr/bin/env bash
# clean-for-production.sh — Remove non-essential files/dirs for production ARM64 build.
# Usage: bash scripts/clean-for-production.sh [--dry-run]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[DRY-RUN] No files will be deleted. Remove --dry-run to execute."
fi

declare -a DIRS_TO_REMOVE=(
    tests
    cli
    docs
    gitbook
    i18n
    .github
    .vscode
    skills
)

declare -a FILES_TO_REMOVE=(
    Dockerfile
    docker-compose.yml
    DOCKER.md
    DEPLOYMENT_GUIDE.md
    captain-definition
    start.sh
    .env.production
)

removed_dirs=()
removed_files=()
skipped=()

echo "=== 9Router Production Cleanup ==="
echo ""
echo "--- Directories ---"
for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [[ -d "$ROOT/$dir" ]]; then
        size_mb=$(du -sm "$ROOT/$dir" | cut -f1)
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [WILL REMOVE] $dir/  (${size_mb} MB)"
        else
            rm -rf "$ROOT/$dir"
            removed_dirs+=("$dir:$size_mb")
            echo "  [REMOVED] $dir/ ($size_mb MB)"
        fi
    else
        echo "  [SKIP] $dir/ (not found)"
        skipped+=("$dir")
    fi
done

echo ""
echo "--- Root Files ---"
for file in "${FILES_TO_REMOVE[@]}"; do
    if [[ -f "$ROOT/$file" ]]; then
        size_kb=$(du -k "$ROOT/$file" | cut -f1)
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [WILL REMOVE] $file  (${size_kb} KB)"
        else
            rm -f "$ROOT/$file"
            removed_files+=("$file:$size_kb")
            echo "  [REMOVED] $file ($size_kb KB)"
        fi
    else
        echo "  [SKIP] $file (not found)"
        skipped+=("$file")
    fi
done

echo ""
echo "=== Summary ==="
total_mb=0
for entry in "${removed_dirs[@]}"; do
    size="${entry##*:}"
    total_mb=$((total_mb + size))
done
for entry in "${removed_files[@]}"; do
    size="${entry##*:}"
    total_mb=$((total_mb + size / 1024))
done
echo "Space saved: ~${total_mb} MB"
if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "Skipped (not present): ${skipped[*]}"
fi
echo ""
echo "=== Cleanup Complete ==="
