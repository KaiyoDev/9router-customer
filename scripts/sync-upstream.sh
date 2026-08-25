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
#   2. Detect conflicts between custom patches and upstream changes
#   3. Apply .excludes to prevent removed items from reappearing
#   4. Apply .patches/ overlays
#   5. Validate (basic sanity checks)
#   6. Report summary (dry-run) or commit (apply)
# ============================================================
set -euo pipefail

# ── Configuration ──────────────────────────────────────────
# We are on a custom branch (e.g. custom-arm64). Upstream master is the source of truth.
UPSTREAM_REMOTE="origin"
UPSTREAM_REPO="https://github.com/decolua/9router.git"
# The upstream branch we sync FROM (what upstream changed)
UPSTREAM_BRANCH="master"
# The local branch we work ON (our customizations live here)
CUSTOM_BRANCH=""
PATCHES_DIR="production/.patches"
EXCLUDES_FILE="production/.excludes"
BUILD_SCRIPT="production/build-and-deploy.sh"

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
BOLD='\033[1m'

log()    { echo -e "${GREEN}[SYNC]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()   { echo -e "${CYAN}[INFO]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

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

# Ensure we're on a custom branch (not master itself)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "master" ]]; then
    warn "You are on 'master' — create a custom branch first:"
    warn "  git checkout -b custom-arm64"
    exit 1
fi

# Back up current state
BACKUP_BRANCH="sync-backup-$(date +%Y%m%d-%H%M%S)"
info "Creating backup branch: $BACKUP_BRANCH"
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
    info "Current branch : $CURRENT_BRANCH (commit $CURRENT_COMMIT)"
    info "Upstream branch: ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH} (commit $UPSTREAM_COMMIT)"

    if [[ "$UPSTREAM_COMMIT" == "$CURRENT_COMMIT" || "$UPSTREAM_COMMIT" == "none" ]]; then
        log "Already up-to-date with upstream (or upstream branch not found)."
        exit 0
    fi

    # Show what upstream changed
    echo ""
    info "Upstream changes since last sync:"
    git log --oneline "$CURRENT_COMMIT..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null | head -20 || \
        git log --oneline -10 "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"
else
    info "[dry-run] Would fetch upstream changes."
fi

# ── Step 2: Preview diff ──────────────────────────────────
section "2. Preview: What upstream would change"

if $APPLY; then
    DIFF_OUTPUT=$(git diff --stat "$CURRENT_COMMIT..${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || true)
    if [[ -n "$DIFF_OUTPUT" ]]; then
        echo "$DIFF_OUTPUT"
    else
        log "No file-level changes detected."
    fi
else
    info "[dry-run] Would show upstream diff here."
fi

# ── Step 3: Check patch conflicts ─────────────────────────
section "3. Checking custom patches for conflicts"

CONFLICTS=()
if [[ -d "$PATCHES_DIR" ]]; then
    for patch_file in "$PATCHES_DIR"/*.patch; do
        [[ -f "$patch_file" ]] || continue
        info "Checking: $(basename "$patch_file")"
        if $APPLY; then
            # Try applying patch to upstream temp checkout to detect conflicts
            TEMP_DIR=$(mktemp -d)
            git clone --depth=1 --no-checkout "$UPSTREAM_REPO" "$TEMP_DIR" 2>/dev/null || true
            if [[ -d "$TEMP_DIR" ]]; then
                (cd "$TEMP_DIR" && \
                    git checkout "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || \
                    git checkout -b temp-upstream "${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}" 2>/dev/null || true) && \
                    if git apply --check "$patch_file" 2>/dev/null; then
                        log "  ✓ No conflicts"
                    else
                        warn "  ⚠ Possible conflict — manual review needed"
                        CONFLICTS+=("$(basename "$patch_file")")
                    fi
            fi
            rm -rf "$TEMP_DIR"
        fi
    done
fi

if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
    echo ""
    error "Conflicts detected in patches: ${CONFLICTS[*]}"
    error "Review and resolve before continuing."
    if ! $APPLY; then
        info "(Run with --apply to see detailed conflict info)"
    fi
fi

# ── Step 4: Apply exclusions ──────────────────────────────
section "4. Exclusion rules (permanent removals)"

if [[ ! -f "$EXCLUDES_FILE" ]]; then
    warn "No .excludes file found at $EXCLUDES_FILE"
else
    EXCLUDED_COUNT=0
    while IFS= read -r pattern; do
        # Skip comments and empty lines
        [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
        EXCLUDED_COUNT=$((EXCLUDED_COUNT + 1))
        if $APPLY; then
            # Remove matching files/dirs if they exist
            # Use find with -maxdepth 1 to avoid recursing into excluded dirs
            while IFS= read -r match; do
                if [[ -n "$match" && -e "$match" ]]; then
                    if [[ -d "$match" ]]; then
                        rm -rf "$match"
                        log "  Removed: $match/"
                    elif [[ -f "$match" ]]; then
                        rm -f "$match"
                        log "  Removed: $match"
                    fi
                fi
            done < <(find . -maxdepth 1 -name "$pattern" 2>/dev/null)
        else
            info "  [dry-run] Would exclude: $pattern"
        fi
    done < "$EXCLUDES_FILE"
    log "Processed $EXCLUDED_COUNT exclusion rules."
fi

# ── Step 5: Apply custom patches ──────────────────────────
section "5. Applying custom patches"

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
else
    info "No patches directory found."
fi

# ── Step 6: Validation ────────────────────────────────────
section "6. Validation"

VALID=true

# Check essential files exist
for required in "package.json" "production/Containerfile" "src/app" "open-sse"; do
    if $APPLY; then
        if [[ -e "$required" ]]; then
            log "  ✓ $required"
        else
            error "  ✗ Missing required: $required"
            VALID=false
        fi
    fi
done

# Check no Docker remnants
DOCKER_REMNANTS=$(find . -maxdepth 2 -name "Dockerfile" -o -name "docker-compose.yml" -o -name ".dockerignore" 2>/dev/null | grep -v "^./production/" | grep -v "^./node_modules/" || true)
if [[ -n "$DOCKER_REMNANTS" ]]; then
    warn "  Docker remnants still present:"
    echo "$DOCKER_REMNANTS" | sed 's/^/      /'
    if $APPLY; then
        error "  Cannot proceed with Docker artifacts present."
        VALID=false
    fi
else
    log "  ✓ No Docker artifacts"
fi

# Check tests directory
if [[ -d "tests" ]] && $APPLY; then
    warn "  tests/ directory present (will be excluded from production build)"
fi

# ── Step 7: Commit (apply mode) ──────────────────────────
if $APPLY; then
    section "7. Committing changes"

    if ! $VALID; then
        error "Validation failed. Aborting commit."
        exit 1
    fi

    git add -A
    CHANGED=$(git diff --cached --name-only)
    if [[ -z "$CHANGED" ]]; then
        log "Nothing changed — already in sync."
    else
        echo "Changed files:"
        echo "$CHANGED" | sed 's/^/  /'
        echo ""
        log "Committed with message: chore(arm64): upstream sync + custom overrides"
        git commit -m "chore(arm64): upstream sync + custom overrides

Synced from ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH} on branch ${CURRENT_BRANCH}
- Applied $PATCH_COUNT custom patches
- Enforced $EXCLUDED_COUNT exclusion rules
- Removed Docker/CI/dev artifacts per production.excludes"
    fi
fi

# ── Summary ───────────────────────────────────────────────
section "Summary"

if $DRY_RUN; then
    echo "Dry-run complete. No changes were made."
    echo ""
    echo "To apply these changes:"
    echo "  $0 --apply"
    echo ""
    echo "To sync + build + deploy:"
    echo "  $0 --build"
else
    if $VALID; then
        log "Sync completed successfully."
        if $BUILD; then
            echo ""
            info "Running build and deploy..."
            bash "$BUILD_SCRIPT"
        fi
    else
        error "Sync completed with validation errors. Review above."
        exit 1
    fi
fi

echo ""
info "Backup branch available: $BACKUP_BRANCH"
info "To restore: git reset --hard $BACKUP_BRANCH"
