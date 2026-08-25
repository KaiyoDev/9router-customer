#!/usr/bin/env bash
# ============================================================
# 9Router ARM64 — Upstream Sync Script (Windows-compatible)
#
# Usage:
#   bash scripts/sync-upstream.sh              # dry-run preview
#   bash scripts/sync-upstream.sh --apply      # apply changes
#   bash scripts/sync-upstream.sh --build      # sync + build + deploy
#
# Workflow:
#   1. Fetch upstream (read-only)
#   2. Compare upstream vs local — detect new files, changed files
#   3. CHECK REMOVED-FILES MANIFEST — stop if upstream re-added deleted items
#   4. CHECK CUSTOM ARTIFACTS — verify Status UI, production/ still intact
#   5. Apply .excludes (permanent removals)
#   6. Apply .patches/ overlays
#   7. Validate (essential files, no Docker remnants)
#   8. Build check (npm run build) — FAIL if broken
#   9. Commit (apply mode) or report (dry-run)
# ============================================================
set -euo pipefail

# ── Configuration ──────────────────────────────────────────
UPSTREAM_REMOTE="origin"
UPSTREAM_REPO="https://github.com/decolua/9router.git"
UPSTREAM_BRANCH="master"

PATCHES_DIR="production/.patches"
EXCLUDES_FILE="production/.excludes"
REMOVED_FILES_MANIFEST="production/removed-files.txt"
REMOVED_DEPS_MANIFEST="production/removed-dependencies.txt"
BUILD_SCRIPT="production/build-and-deploy.sh"
CUSTOM_ARTIFACTS_DIR="src/app/status"

DRY_RUN=true
APPLY=false
BUILD=false

# ── Parse arguments ────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)  APPLY=true;  DRY_RUN=false ;;
        --build)  BUILD=true;  DRY_RUN=false; APPLY=true ;;
        --dry-run) DRY_RUN=true; APPLY=false ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

log()    { echo -e "${GREEN}[SYNC]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()   { echo -e "${CYAN}[INFO]${NC} $*"; }
check()  { echo -e "${GREEN}[OK]${NC}  $*"; }
fail()   { echo -e "${RED}[FAIL]${NC} $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}\n"; }

# ── Pre-flight checks ─────────────────────────────────────
section "Pre-flight"

if ! command -v git &>/dev/null; then
    error "git is required but not found"; exit 1
fi

if [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    error "Not inside a git repository"; exit 1
fi

# Ensure upstream remote exists
if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
    info "Adding upstream remote: $UPSTREAM_REMOTE → $UPSTREAM_REPO"
    if $APPLY; then
        git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_REPO"
    else
        warn "Upstream remote not configured. Run with --apply to add it."
    fi
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "master" ]]; then
    warn "You are on 'master' — create a custom branch first:"
    warn "  git checkout -b custom-arm64"
    exit 1
fi

BACKUP_BRANCH="sync-backup-$(date +%Y%m%d-%H%M%S)"
info "Backup branch: $BACKUP_BRANCH"
if $APPLY; then
    git branch "$BACKUP_BRANCH" HEAD
else
    info "[dry-run] Would create backup branch: $BACKUP_BRANCH"
fi

# ── Step 1: Fetch upstream ────────────────────────────────
section "1. Fetching upstream"

if $APPLY; then
    git fetch "$UPSTREAM_REMOTE" --prune
    UPSTREAM_COMMIT=$(git rev-parse "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || echo "none")
    CURRENT_COMMIT=$(git rev-parse HEAD)
    info "Local        : $CURRENT_BRANCH @ ${CURRENT_COMMIT:0:8}"
    info "Upstream     : ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH} @ ${UPSTREAM_COMMIT:0:8}"

    if [[ "$UPSTREAM_COMMIT" == "$CURRENT_COMMIT" || "$UPSTREAM_COMMIT" == "none" ]]; then
        log "Already up-to-date with upstream."
        exit 0
    fi

    NEW_COMMITS=$(git log --oneline "$CURRENT_COMMIT..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null | wc -l | tr -d ' ')
    info "New upstream commits: $NEW_COMMITS"
    echo ""
    git log --oneline "$CURRENT_COMMIT..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null | head -15 || true
else
    info "[dry-run] Would fetch upstream changes."
fi

# ── Step 2: Detect what upstream would change ─────────────
section "2. Diff analysis: upstream vs local"

UPSTREAM_ADDED=()
UPSTREAM_MODIFIED=()
UPSTREAM_DELETED=()

if $APPLY; then
    # Files upstream has that we don't (new files from upstream)
    while IFS= read -r f; do
        [[ -n "$f" ]] && UPSTREAM_ADDED+=("$f")
    done < <(git diff --name-only "$CURRENT_COMMIT" "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null | grep '^A\|^' || true)

    # Use name-status to categorize
    while IFS=$'\t' read -r status file; do
        [[ -z "$file" ]] && continue
        case "$status" in
            A)  UPSTREAM_ADDED+=("$file") ;;
            M)  UPSTREAM_MODIFIED+=("$file") ;;
            D)  UPSTREAM_DELETED+=("$file") ;;
            *)  ;;
        esac
    done < <(git diff --name-status "$CURRENT_COMMIT" "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || true)
fi

# ── Step 3: CHECK REMOVED-FILES MANIFEST ─────────────────
section "3. Removed-files manifest check"

if [[ ! -f "$REMOVED_FILES_MANIFEST" ]]; then
    warn "No removed-files.txt manifest found — skipping manifest check."
else
    CONFLICTS=()
    info "Checking ${#UPSTREAM_ADDED[@]} upstream-added files against manifest…"

    # Build associative array of removed paths
    declare -A REMOVED_PATHS
    while IFS= read -r line; do
        line="${line%%#*}"        # strip comment
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"  # trim
        [[ -z "$line" ]] && continue
        REMOVED_PATHS["$line"]=1
    done < "$REMOVED_FILES_MANIFEST"

    for added_file in "${UPSTREAM_ADDED[@]}"; do
        matched=false
        for removed_pattern in "${!REMOVED_PATHS[@]}"; do
            # Exact match
            if [[ "$added_file" == "$removed_pattern" ]]; then
                matched=true
                break
            fi
            # Directory prefix match (e.g. "tests/" matches "tests/unit/foo.js")
            if [[ "$removed_pattern" == */ && "$added_file" == ${removed_pattern}* ]]; then
                matched=true
                break
            fi
            # Glob match
            if [[ "$added_file" == $removed_pattern ]]; then
                matched=true
                break
            fi
        done
        if $matched; then
            CONFLICTS+=("$added_file")
        fi
    done

    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        echo ""
        error "UPSTREAM RE-ADDED FILES THAT SHOULD BE REMOVED:"
        for c in "${CONFLICTS[@]}"; do
            echo -e "  ${RED}✗${NC} $c"
        done
        echo ""
        error "These files were intentionally removed from the ARM64 distribution."
        error "The sync has STOPPED. Review and decide:"
        error "  1. Remove them manually, then re-run with --apply"
        error "  2. Update $REMOVED_FILES_MANIFEST if they should now be kept"
        if ! $APPLY; then
            info "(Run with --apply to see conflict details)"
        fi
        exit 1
    else
        check "No removed-files conflicts detected"
    fi
fi

# ── Step 4: CHECK CUSTOM ARTIFACTS ────────────────────────
section "4. Custom artifacts integrity check"

declare -A CUSTOM_FILES
while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == "protected:"* ]] && continue
    CUSTOM_FILES["$line"]=1
done <<< "
# Status UI — must survive every upstream sync
src/app/status/layout.js
src/app/status/page.js
src/app/status/README.md
src/app/status/components/StatusHeader.js
src/app/status/components/OverallStatusCard.js
src/app/status/components/ServiceStatus.js
src/app/status/components/ProviderGrid.js
src/app/status/components/UptimeStats.js
src/app/status/components/UsageStats.js
src/app/status/components/IncidentTimeline.js
src/app/status/components/MaintenanceBanner.js
src/app/status/components/LastUpdated.js
src/app/status/components/StatusIndicator.js
src/app/status/hooks/useStatusData.js
src/app/status/lib/mockData.js
src/app/status/lib/mockUptime.js
src/app/status/lib/types.js
src/app/status/lib/statusHelpers.js
# API routes
src/app/api/status/route.js
src/app/api/status/providers/route.js
# Production build assets
production/Containerfile
production/9router.container
production/build-and-deploy.sh
production/.excludes
production/.patches/001-low-memory-mode.patch
production/.patches/002-next-config-tweaks.patch
production/.patches/003-reduce-memory-usage.patch
production/README.md
# Sync/deploy scripts
scripts/sync-upstream.sh
scripts/deploy-production.sh
scripts/benchmark-memory.sh
scripts/clean-for-production.sh
scripts/clean-for-production.ps1
# Config templates
custom/config/.env.production
"

MISSING_CUSTOM=()
for cf in "${!CUSTOM_FILES[@]}"; do
    if [[ ! -e "$cf" ]]; then
        MISSING_CUSTOM+=("$cf")
    fi
done

if [[ ${#MISSING_CUSTOM[@]} -gt 0 ]]; then
    echo ""
    error "MISSING CUSTOM ARTIFACTS (may have been overwritten by upstream):"
    for mc in "${MISSING_CUSTOM[@]}"; do
        echo -e "  ${RED}✗${NC} $mc"
    done
    echo ""
    error "Some custom files are missing! The sync has STOPPED."
    error "Restore from backup: git checkout $BACKUP_BRANCH -- <file>"
    if ! $APPLY; then
        info "(Run with --apply to attempt restore)"
    fi
    exit 1
else
    check "${#CUSTOM_FILES[@]} custom artifacts intact"
fi

# ── Step 5: Show summary of upstream changes ──────────────
section "5. Change summary"

ADDED_COUNT=${#UPSTREAM_ADDED[@]}
MODIFIED_COUNT=${#UPSTREAM_MODIFIED[@]}
DELETED_COUNT=${#UPSTREAM_DELETED[@]}

info "Upstream changes:"
info "  Added    : $ADDED_COUNT file(s)"
info "  Modified : $MODIFIED_COUNT file(s)"
info "  Deleted  : $DELETED_COUNT file(s)"

if [[ $ADDED_COUNT -gt 0 ]] && $APPLY; then
    echo ""
    info "New files from upstream:"
    for f in "${UPSTREAM_ADDED[@]}"; do
        echo "  + $f"
    done
fi

if [[ $MODIFIED_COUNT -gt 0 ]] && $APPLY; then
    echo ""
    info "Modified files (review recommended):"
    for f in "${UPSTREAM_MODIFIED[@]:0:10}"; do
        echo "  ~ $f"
    done
    if [[ $MODIFIED_COUNT -gt 10 ]]; then
        info "  … and $((MODIFIED_COUNT - 10)) more"
    fi
fi

# ── Step 6: Apply exclusions ──────────────────────────────
section "6. Applying exclusion rules"

if [[ ! -f "$EXCLUDES_FILE" ]]; then
    warn "No .excludes file found."
else
    EXCLUDED_COUNT=0
    while IFS= read -r pattern; do
        [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
        EXCLUDED_COUNT=$((EXCLUDED_COUNT + 1))
        if $APPLY; then
            while IFS= read -r match; do
                [[ -z "$match" || ! -e "$match" ]] && continue
                if [[ -d "$match" ]]; then
                    rm -rf "$match"
                    log "  Removed: $match/"
                elif [[ -f "$match" ]]; then
                    rm -f "$match"
                    log "  Removed: $match"
                fi
            done < <(find . -maxdepth 1 -name "${pattern%/}" 2>/dev/null; find . -maxdepth 1 -name "${pattern}" 2>/dev/null)
        fi
    done < "$EXCLUDES_FILE"
    log "Exclusion rules applied: $EXCLUDED_COUNT"
fi

# ── Step 7: Merge upstream changes ────────────────────────
section "7. Merging upstream changes"

if $APPLY; then
    info "Merging ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH} → $CURRENT_BRANCH …"

    # Fast-forward if possible
    if git merge-base --is-ancestor "$CURRENT_COMMIT" "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null; then
        info "Fast-forward available."
        git merge --ff-only "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" || {
            error "Fast-forward failed — conflicts detected."
            error "Resolve conflicts, then: git merge --continue"
            exit 1
        }
    else
        info "No fast-forward — attempting merge…"
        git merge --no-edit "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" || {
            error "Merge conflicts detected!"
            error "Resolve manually, then: git merge --continue"
            exit 1
        }
    fi
    log "Merge completed."
else
    info "[dry-run] Would merge upstream changes."
fi

# ── Step 8: Apply patches ─────────────────────────────────
section "8. Applying custom patches"

if [[ -d "$PATCHES_DIR" ]]; then
    PATCH_COUNT=0
    for patch_file in "$PATCHES_DIR"/*.patch; do
        [[ -f "$patch_file" ]] || continue
        PATCH_COUNT=$((PATCH_COUNT + 1))
        info "Applying: $(basename "$patch_file")"
        if $APPLY; then
            if git apply --reject "$patch_file" 2>/dev/null; then
                log "  ✓ Applied cleanly"
            else
                warn "  ⚠ Partial apply — check .rej files"
            fi
        else
            info "  [dry-run] Would apply"
        fi
    done
    log "Total patches: $PATCH_COUNT"
fi

# ── Step 9: Validation ────────────────────────────────────
section "9. Validation"

VALID=true

for required in "package.json" "production/Containerfile" "src/app" "open-sse"; do
    if $APPLY; then
        if [[ -e "$required" ]]; then
            check "$required"
        else
            error "Missing required: $required"
            VALID=false
        fi
    fi
done

# Docker remnants check
DOCKER_REMNANTS=$(find . -maxdepth 2 \( -name "Dockerfile" -o -name "docker-compose.yml" -o -name ".dockerignore" \) \
    -not -path "./production/*" -not -path "./node_modules/*" 2>/dev/null | grep -v "^$" || true)
if [[ -n "$DOCKER_REMNANTS" ]]; then
    warn "Docker artifacts still present:"
    echo "$DOCKER_REMNANTS" | sed 's/^/  /'
    if $APPLY; then
        error "Cannot proceed with Docker artifacts present."
        VALID=false
    fi
else
    check "No Docker artifacts"
fi

# Build check (if --build or --apply)
if $APPLY; then
    section "10. Build check"
    info "Running npm ci + next build …"
    if npm ci --prefer-offline 2>&1 | tail -3; then
        if npm run build 2>&1 | tail -20; then
            check "Build succeeded"
        else
            error "Build FAILED — upstream changes may have broken the app."
            error "Do NOT deploy. Review errors above."
            VALID=false
        fi
    else
        error "npm ci failed — dependency issues."
        VALID=false
    fi
fi

# ── Step 10: Commit ───────────────────────────────────────
if $APPLY && $VALID; then
    section "11. Committing"

    git add -A
    CHANGED=$(git diff --cached --name-only)
    if [[ -z "$CHANGED" ]]; then
        log "Nothing changed — already in sync."
    else
        CHANGED_COUNT=$(echo "$CHANGED" | wc -l | tr -d ' ')
        echo ""
        info "Changed files ($CHANGED_COUNT):"
        echo "$CHANGED" | sed 's/^/  /' | head -30
        [[ $CHANGED_COUNT -gt 30 ]] && info "  … and $((CHANGED_COUNT - 30)) more"
        echo ""

        COMMIT_MSG="chore(arm64): upstream sync from ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}

Commits merged: $(git log --oneline $CURRENT_COMMIT..HEAD | wc -l | tr -d ' ')
Files changed: $CHANGED_COUNT
Patches applied: $PATCH_COUNT
Exclusions enforced: $EXCLUDED_COUNT
Removed-files manifest: checked ✓
Custom artifacts: verified ✓
Build: $([ "$VALID" = true ] && echo 'PASS' || echo 'FAIL')

Manifest: $REMOVED_FILES_MANIFEST"

        git commit -m "$COMMIT_MSG"
        log "Committed."
    fi
fi

# ── Summary ───────────────────────────────────────────────
section "Summary"

if $DRY_RUN; then
    echo -e "${BOLD}Dry-run complete — no changes were made.${NC}"
    echo ""
    echo "  ${GREEN}→${NC}  bash scripts/sync-upstream.sh --apply   (preview + merge)"
    echo "  ${GREEN}→${NC}  bash scripts/sync-upstream.sh --build    (merge + validate + deploy)"
else
    if $VALID; then
        log "Sync completed successfully."
        if $BUILD; then
            echo ""
            info "Running deployment…"
            bash "$BUILD_SCRIPT"
        fi
    else
        error "Sync completed with errors. Review output above."
        error "Backup branch: $BACKUP_BRANCH"
        error "To restore: git reset --hard $BACKUP_BRANCH"
        exit 1
    fi
fi

echo ""
info "Backup branch: $BACKUP_BRANCH"
info "To restore:     git reset --hard $BACKUP_BRANCH"
info "To push:        git push $UPSTREAM_REMOTE $CURRENT_BRANCH"
