#!/usr/bin/env bash
# ============================================================
# 9Router ARM64 — Build & Deploy Script
#
# Builds the Podman image, health-checks it, switches the
# running container, and rolls back on failure.
#
# Usage:
#   ./production/build-and-deploy.sh           # build + deploy
#   ./production/build-and-deploy.sh --dry-run # show what would happen
#   ./production/build-and-deploy.sh --rollback # revert to previous image
#
# Image tagging:
#   localhost/9router:<git-short-sha>-<date>
#   e.g. localhost/9router:a1b2c3d-20250115
#
# Rollback:
#   Keeps the previous image tag; --rollback reverts to it.
# ============================================================
set -euo pipefail

DRY_RUN=false
ROLLBACK=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --rollback) ROLLBACK=true ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
    shift
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()    { echo -e "${GREEN}[BUILD]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()   { echo -e "${CYAN}[INFO]${NC} $*"; }
section(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

# ── Resolve paths ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_NAME="localhost/9router"
GIT_SHA=$(git rev-parse --short HEAD)
GIT_DATE=$(date +%Y%m%d)
IMAGE_TAG="${GIT_SHA}-${GIT_DATE}"
PREV_IMAGE_TAG=""
CONTAINER_NAME="9router"

# ── Rollback mode ──────────────────────────────────────────
if $ROLLBACK; then
    section "Rollback"
    # Find the previous image tag from podman images
    PREV_IMAGE_TAG=$(podman images --format "{{.Repository}}:{{.Tag}}" \
        "${IMAGE_NAME}" 2>/dev/null \
        | grep -v "^${IMAGE_NAME}:current$" \
        | grep -v "^${IMAGE_NAME}:${IMAGE_TAG}$" \
        | head -1 || true)

    if [[ -z "$PREV_IMAGE_TAG" ]]; then
        error "No previous image found for rollback."
        error "Available images:"
        podman images "$IMAGE_NAME" 2>/dev/null || true
        exit 1
    fi

    info "Rolling back to: $PREV_IMAGE_TAG"
    if $DRY_RUN; then
        info "[dry-run] Would update Quadlet to $PREV_IMAGE_TAG and restart service"
        exit 0
    fi

    # Update Quadlet file with previous image tag
    QUADLET_FILE="${HOME}/.config/containers/systemd/9router.container"
    if [[ -f "$QUADLET_FILE" ]]; then
        sed -i "s|^Image=.*|Image=${IMAGE_NAME}:${PREV_IMAGE_TAG}|" "$QUADLET_FILE"
        log "Updated Quadlet: Image=${IMAGE_NAME}:${PREV_IMAGE_TAG}"
    else
        error "Quadlet file not found: $QUADLET_FILE"
        exit 1
    fi

    # Reload systemd and restart
    systemctl --user daemon-reload
    systemctl --user restart "$CONTAINER_NAME"
    sleep 3

    if systemctl --user is-active "$CONTAINER_NAME" &>/dev/null; then
        log "Rolled back to $PREV_IMAGE_TAG successfully"
    else
        error "Failed to start after rollback. Check: systemctl --user status $CONTAINER_NAME"
        exit 1
    fi
    exit 0
fi

# ── Check prerequisites ────────────────────────────────────
section "Prerequisites"

if ! command -v podman &>/dev/null; then
    error "podman not found. Install: sudo dnf install podman"
    exit 1
fi

if ! podman info &>/dev/null; then
    error "podman daemon not running. Start: systemctl --user start podman"
    exit 1
fi

# Save current image tag for rollback reference
if podman images --format "{{.Tag}}" "$IMAGE_NAME" 2>/dev/null | grep -q .; then
    PREV_IMAGE_TAG="$IMAGE_NAME:$(podman images --format "{{.Tag}}" "$IMAGE_NAME" | head -1)"
    info "Current image: $PREV_IMAGE_TAG"
fi

# ── Build ──────────────────────────────────────────────────
section "Building image"

BUILD_CMD=(
    podman build
    --platform linux/arm64
    --tag "${IMAGE_NAME}:${IMAGE_TAG}"
    --tag "${IMAGE_NAME}:current"
    -f production/Containerfile
    .
)

if $DRY_RUN; then
    info "[dry-run] Would run:"
    echo "  ${BUILD_CMD[*]}"
    exit 0
fi

log "Building: ${IMAGE_TAG}"
log "  Platform : linux/arm64"
log "  Context  : $REPO_ROOT"
echo ""

"${BUILD_CMD[@]}" 2>&1 | tail -20

log "Image built: ${IMAGE_NAME}:${IMAGE_TAG}"

# ── Healthcheck ────────────────────────────────────────────
section "Healthcheck (dry-run container)"

# Run a temporary container to verify the image starts correctly
HC_CONTAINER="9router-hc-${IMAGE_TAG}"
HC_PORT=$(shuf -i 21000-22000 -n 1)

if $DRY_RUN; then
    info "[dry-run] Would start temp container on port $HC_PORT"
    info "[dry-run] Would run healthcheck against http://127.0.0.1:${HC_PORT}/api/auth/status"
    info "[dry-run] Would switch service to ${IMAGE_TAG} on success"
    exit 0
fi

log "Starting healthcheck container..."
podman rm -f "$HC_CONTAINER" 2>/dev/null || true
podman run -d \
    --name "$HC_CONTAINER" \
    --publish "${HC_PORT}:20130" \
    --env NODE_ENV=production \
    --env PORT=20130 \
    --env HOSTNAME=0.0.0.0 \
    --env DATA_DIR=/app/data \
    --env ENABLE_REQUEST_LOGS=false \
    --env OBSERVABILITY_ENABLED=false \
    --env NODE_OPTIONS="--max-old-space-size=512 --no-warnings" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

# Wait for container to start
sleep 5

# Healthcheck loop (max 60s)
MAX_WAIT=60
ELAPSED=0
HC_PASSED=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 5 "http://127.0.0.1:${HC_PORT}/api/auth/status" 2>/dev/null || echo "000")
    if [[ "$STATUS" == "200" ]]; then
        HC_PASSED=true
        log "Healthcheck PASSED (HTTP $STATUS after ${ELAPSED}s)"
        break
    fi
    warn "Healthcheck: HTTP $STATUS (waiting ${ELAPSED}s/${MAX_WAIT}s)..."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

# Clean up healthcheck container
podman rm -f "$HC_CONTAINER" 2>/dev/null || true

if ! $HC_PASSED; then
    error "Healthcheck FAILED after ${MAX_WAIT}s."
    error "Keeping old image: $PREV_IMAGE_TAG"
    error "Inspect logs: podman logs $(podman ps -q --filter name=$CONTAINER_NAME 2>/dev/null || echo 'N/A')"
    exit 1
fi

# ── Deploy ─────────────────────────────────────────────────
section "Deploying to systemd"

if $DRY_RUN; then
    info "[dry-run] Would update Quadlet image tag to: ${IMAGE_TAG}"
    info "[dry-run] Would reload systemd and restart service"
    exit 0
fi

# Stop current container
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

# Update Quadlet file with new image tag
QUADLET_FILE="${HOME}/.config/containers/systemd/9router.container"
if [[ -f "$QUADLET_FILE" ]]; then
    sed -i "s|^Image=.*|Image=${IMAGE_NAME}:${IMAGE_TAG}|" "$QUADLET_FILE"
    log "Updated Quadlet: Image=${IMAGE_NAME}:${IMAGE_TAG}"
else
    warn "Quadlet file not found at $QUADLET_FILE — manual update needed"
fi

# Reload systemd and start
systemctl --user daemon-reload
systemctl --user restart "$CONTAINER_NAME"

# Verify it started
sleep 3
if systemctl --user is-active "$CONTAINER_NAME" &>/dev/null; then
    log "Service RUNNING with image ${IMAGE_TAG}"
else
    warn "Service may have failed. Check: systemctl --user status $CONTAINER_NAME"
fi

# ── Summary ────────────────────────────────────────────────
section "Done"
echo ""
echo -e "  ${GREEN}✓${NC} Image built  : ${BOLD}${IMAGE_NAME}:${IMAGE_TAG}${NC}"
if [[ -n "$PREV_IMAGE_TAG" ]]; then
    echo -e "  ${CYAN}⬡${NC} Rollback to  : ${BOLD}${PREV_IMAGE_TAG}${NC}"
    echo -e "    ${YELLOW}bash ${0} --rollback${NC}"
fi
echo ""
echo "  Status:"
systemctl --user status "$CONTAINER_NAME" --no-pager | head -5
echo ""
echo "  Logs:"
echo "    journalctl --user -u $CONTAINER_NAME -f"
echo ""
