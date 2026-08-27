#!/usr/bin/env bash
# ============================================================
# 9Router ARM64 — Build & Deploy Script
#
# Builds the Podman image, health-checks it, then runs it
# directly with podman run (no systemd/Quadlet dependency).
#
# Usage:
#   ./production/build-and-deploy.sh           # build + deploy
#   ./production/build-and-deploy.sh --dry-run # show what would happen
#   ./production/build-and-deploy.sh --rollback # revert to previous image
#   ./production/build-and-deploy.sh --status   # show current state
#
# Image tagging:
#   localhost/9router:<git-short-sha>-<date>
#   e.g. localhost/9router:a1b2c3d-20260825
#
# Auto-start on boot (optional):
#   podman generate systemd --name 9router --new --files
#   cp ~/.config/containers/systemd/container-9router.service \
#      ~/.config/systemd/user/9router.service
#   systemctl --user enable 9router
# ============================================================
set -euo pipefail

DRY_RUN=false
ROLLBACK=false
STATUS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true ;;
        --rollback)  ROLLBACK=true ;;
        --status)    STATUS=true ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
    shift
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()    { echo -e "${GREEN}[DEPLOY]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()   { echo -e "${CYAN}[INFO]${NC} $*"; }
section(){ echo -e "\n${BOLD}${CYAN}══ $* ══${NC}\n"; }

# ── Resolve paths ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_NAME="localhost/9router"
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_DATE=$(date +%Y%m%d)
IMAGE_TAG="${GIT_SHA}-${GIT_DATE}"
CONTAINER_NAME="9router"

# ── Volumes & dirs ──────────────────────────────────────────
DATA_DIR="${HOME}/.local/share/9router-data"
LOGS_DIR="${HOME}/.local/share/9router-logs"
mkdir -p "$DATA_DIR" "$LOGS_DIR"

# ── Rollback mode ──────────────────────────────────────────
if $ROLLBACK; then
    section "Rollback"
    PREV_IMAGE_TAG=$(podman images --format "{{.Repository}}:{{.Tag}}" \
        "$IMAGE_NAME" 2>/dev/null \
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
        info "[dry-run] Would stop container and restart with $PREV_IMAGE_TAG"
        exit 0
    fi

    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
    run_container "$PREV_IMAGE_TAG"
    exit 0
fi

# ── Status mode ────────────────────────────────────────────
if $STATUS; then
    section "Current Status"
    echo ""
    echo "  Image:"
    podman images "$IMAGE_NAME" --format "    {{.Repository}}:{{.Tag}}  {{.Size}}" 2>/dev/null || echo "    (none)"
    echo ""
    echo "  Container:"
    podman ps -a --filter "name=$CONTAINER_NAME" --format "    {{.Names}}  {{.Status}}  {{.Image}}" 2>/dev/null || echo "    (not running)"
    echo ""
    echo "  Ports:"
    echo "    http://localhost:20130/dashboard"
    echo "    http://localhost:20130/api/auth/status"
    echo ""
    echo "  ${CYAN}Data volume:${NC}  podman volume inspect 9router-data"
    echo "  ${CYAN}Logs volume:${NC}  podman volume inspect 9router-logs"
    echo ""
    echo "  Commands:"
    echo "    podman logs -f $CONTAINER_NAME        # view logs"
    echo "    podman stop $CONTAINER_NAME            # stop"
    echo "    podman start $CONTAINER_NAME           # start"
    echo "    podman restart $CONTAINER_NAME         # restart"
    echo "    bash production/build-and-deploy.sh   # rebuild + redeploy"
    echo "    bash production/build-and-deploy.sh --rollback  # revert"
    exit 0
fi

# ── Check prerequisites ────────────────────────────────────
section "Prerequisites"

if ! command -v podman &>/dev/null; then
    error "podman not found. Install: sudo dnf install podman"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    warn "curl not found — healthcheck will use wget or node"
fi

info "Podman version : $(podman --version 2>/dev/null || echo 'unknown')"
info "Node version   : $(node --version 2>/dev/null || echo 'unknown')"
info "Git commit     : $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo ""

# Save current image tag for rollback reference
PREV_IMAGE_TAG=""
if podman images --format "{{.Tag}}" "$IMAGE_NAME" 2>/dev/null | grep -q .; then
    PREV_IMAGE_TAG="$IMAGE_NAME:$(podman images --format "{{.Tag}}" "$IMAGE_NAME" | head -1)"
    info "Current image  : $PREV_IMAGE_TAG"
fi

# ── Build ──────────────────────────────────────────────────
section "Building image"

if $DRY_RUN; then
    info "[dry-run] Would build: ${IMAGE_TAG}"
    info "[dry-run] Command:"
    echo "  podman build --cgroup-manager=cgroupfs \\"
    echo "    --platform linux/arm64 \\"
    echo "    -t ${IMAGE_NAME}:${IMAGE_TAG} \\"
    echo "    -t ${IMAGE_NAME}:current \\"
    echo "    -f production/Containerfile ."
    exit 0
fi

log "Building: ${IMAGE_TAG}"
log "  Platform : linux/arm64"
log "  Context  : $REPO_ROOT"
echo ""

podman build --cgroup-manager=cgroupfs \
    --platform linux/arm64 \
    --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
    --tag "${IMAGE_NAME}:current" \
    -f production/Containerfile . 2>&1 | tail -15

log "✓ Image built: ${IMAGE_NAME}:${IMAGE_TAG}"

# ── Healthcheck ────────────────────────────────────────────
section "Healthcheck (dry-run container)"

HC_CONTAINER="9router-hc-${IMAGE_TAG}"
HC_PORT=$(shuf -i 21000-22000 -n 1 2>/dev/null || echo $((21000 + RANDOM % 1000)))

if $DRY_RUN; then
    info "[dry-run] Would start temp container on port $HC_PORT"
    info "[dry-run] Would run healthcheck against http://127.0.0.1:${HC_PORT}/api/auth/status"
    info "[dry-run] Would start production container on port 20130"
    exit 0
fi

log "Starting healthcheck container..."
podman rm -f "$HC_CONTAINER" 2>/dev/null || true
podman run -d \
    --cgroup-manager=cgroupfs \
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
    # Try curl first, fall back to node
    if command -v curl &>/dev/null; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 "http://127.0.0.1:${HC_PORT}/api/auth/status" 2>/dev/null || echo "000")
    else
        STATUS=$(node -e "
            const http=require('http');
            const req=http.request({hostname:'127.0.0.1',port:${HC_PORT},path:'/api/auth/status',timeout:5000},res=>{
                console.log(res.statusCode);process.exit(0);
            });
            req.on('error',()=>{console.log('000');process.exit(0);});
            req.end();
        " 2>/dev/null || echo "000")
    fi

    if [[ "$STATUS" == "200" ]]; then
        HC_PASSED=true
        log "✓ Healthcheck PASSED (HTTP $STATUS after ${ELAPSED}s)"
        break
    fi
    warn "Healthcheck: HTTP $STATUS (waiting ${ELAPSED}s/${MAX_WAIT}s)..."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

# Clean up healthcheck container
podman rm -f "$HC_CONTAINER" 2>/dev/null || true

if ! $HC_PASSED; then
    error "✗ Healthcheck FAILED after ${MAX_WAIT}s."
    error "Keeping old image: $PREV_IMAGE_TAG"
    error "Inspect: podman logs $(podman ps -aq --filter name=$CONTAINER_NAME 2>/dev/null || echo N/A)"
    exit 1
fi

# ── Deploy ─────────────────────────────────────────────────
section "Deploying container"

if $DRY_RUN; then
    info "[dry-run] Would stop old container and start new one"
    info "[dry-run] Image : ${IMAGE_NAME}:${IMAGE_TAG}"
    info "[dry-run] Port  : 20130"
    info "[dry-run] Data  : $DATA_DIR"
    info "[dry-run] Logs  : $LOGS_DIR"
    exit 0
fi

# Stop and remove old container if running
if podman ps -q --filter "name=$CONTAINER_NAME" 2>/dev/null | grep -q .; then
    log "Stopping old container..."
    podman stop "$CONTAINER_NAME" 2>/dev/null || true
    podman rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Ensure Podman volumes exist
podman volume create 9router-data 2>/dev/null || true
podman volume create 9router-logs 2>/dev/null || true

# Start fresh container with all settings
log "Starting ${CONTAINER_NAME} with image ${IMAGE_TAG}..."

# DEFAULT_PASSWORD can be overridden via env var; falls back to Kaiyo-specific default
DEFAULT_PASSWORD="${INITIAL_PASSWORD:-Kaiyo2024Secure!}"

podman run -d \
    --cgroup-manager=cgroupfs \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --publish 20130:20130 \
    --memory 1024m \
    --memory-swap 1024m \
    --env NODE_ENV=production \
    --env PORT=20130 \
    --env HOSTNAME=0.0.0.0 \
    --env LOW_MEMORY_MODE=1 \
    --env NODE_OPTIONS="--max-old-space-size=512 --no-warnings" \
    --env ENABLE_REQUEST_LOGS=false \
    --env OBSERVABILITY_ENABLED=false \
    --env DATA_DIR=/app/data \
    --env INITIAL_PASSWORD="${DEFAULT_PASSWORD}" \
    --volume 9router-data:/app/data \
    --volume 9router-logs:/home/node/.9router \
    --security-opt no-new-privileges:true \
    "${IMAGE_NAME}:${IMAGE_TAG}"

# Verify it started
sleep 3
if podman ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}" 2>/dev/null | grep -qi "up"; then
    log "✓ Container RUNNING with image ${IMAGE_TAG}"
else
    warn "Container may have failed to start. Check logs below:"
    podman logs --tail 20 "$CONTAINER_NAME" 2>/dev/null || true
    error "To fix: podman logs $CONTAINER_NAME"
    exit 1
fi

# ── Summary ────────────────────────────────────────────────
section "Done"
echo ""
echo -e "  ${GREEN}✓${NC} Image built : ${BOLD}${IMAGE_NAME}:${IMAGE_TAG}${NC}"
echo -e "  ${GREEN}✓${NC} Container   : ${BOLD}${CONTAINER_NAME}${NC} (running)"
echo ""
echo -e "  ${CYAN}→${NC} Dashboard  : http://localhost:20130/dashboard"
echo -e "  ${CYAN}→${NC} API        : http://localhost:20130/v1"
echo -e "  ${CYAN}→${NC} Status     : http://localhost:20130/status"
echo ""
echo -e "  ${CYAN}Management:${NC}"
echo -e "    ${YELLOW}podman logs -f ${CONTAINER_NAME}${NC}          # view logs"
echo -e "    ${YELLOW}podman stop ${CONTAINER_NAME}${NC}              # stop"
echo -e "    ${YELLOW}podman start ${CONTAINER_NAME}${NC}             # start"
echo -e "    ${YELLOW}podman restart ${CONTAINER_NAME}${NC}           # restart"
echo ""
if [[ -n "$PREV_IMAGE_TAG" ]]; then
    echo -e "  ${CYAN}Rollback:${NC}"
    echo -e "    ${YELLOW}bash ${0} --rollback${NC}                  # revert to $PREV_IMAGE_TAG"
    echo ""
fi
echo -e "  ${CYAN}Auto-start on boot:${NC}"
echo -e "    ${YELLOW}podman generate systemd --name ${CONTAINER_NAME} --new --files${NC}"
echo -e "    ${YELLOW}cp ~/.config/containers/systemd/container-${CONTAINER_NAME}.service \\${NC}"
echo -e "       ~/.config/systemd/user/${CONTAINER_NAME}.service${NC}"
echo -e "    ${YELLOW}systemctl --user enable ${CONTAINER_NAME}${NC}"
echo ""
