#!/usr/bin/env bash
# ============================================================
# 9Router ARM64 — Memory & Performance Benchmark Script
# Run on the TV Box after deployment:
#   chmod +x scripts/benchmark-memory.sh
#   ./scripts/benchmark-memory.sh
# ============================================================
set -euo pipefail

CONTAINER_NAME="9router"
HEALTH_ENDPOINT="http://localhost:20130/api/auth/status"
BENCH_DURATION_SEC=${1:-30}
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "========================================"
echo "  9Router ARM64 Benchmark Suite"
echo "========================================"
echo ""

# ── 1. System overview ─────────────────────────────────────
echo -e "${YELLOW}[1/5] System Overview${NC}"
echo "---"
echo "Architecture : $(uname -m)"
echo "Kernel       : $(uname -r)"
echo "CPU cores    : $(nproc)"
echo "Total RAM    : $(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
echo "Available RAM: $(awk '/MemAvailable/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
SWAP_TOTAL=$(awk '/^SwapTotal/ {print $2}' /proc/meminfo)
if [[ "$SWAP_TOTAL" -eq 0 ]]; then
    echo "Swap         : 0 MB (none)"
else
    echo "Swap         : $(awk '{printf "%.0f MB", $1/1024}' /proc/meminfo)"
fi
echo "Disk total   : $(df -BG / | awk 'NR==2 {print $2}')"
echo "Disk avail   : $(df -BG / | awk 'NR==2 {print $4}')"
echo ""

# ── 2. Container status ────────────────────────────────────
echo -e "${YELLOW}[2/5] Container Status${NC}"
echo "---"
if command -v podman &>/dev/null; then
    PODMAN_CMD="podman"
elif command -v docker &>/dev/null; then
    PODMAN_CMD="docker"
else
    echo -e "${RED}ERROR: Neither podman nor docker found${NC}"
    exit 1
fi

$PODMAN_CMD ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "Container not running"
echo ""

# ── 3. Memory baseline (idle) ──────────────────────────────
echo -e "${YELLOW}[3/5] Memory Baseline (Idle)${NC}"
echo "---"

get_container_rss() {
    local cid
    cid=$($PODMAN_CMD ps --filter "name=${CONTAINER_NAME}" --format "{{.ID}}" 2>/dev/null || echo "")
    if [[ -z "$cid" ]]; then
        echo "N/A"
        return
    fi
    local cgpath="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/${CONTAINER_NAME}.scope"
    if [[ -f "${cgpath}/memory.current" ]]; then
        awk '{printf "%.0f MB", $1/1024/1024}' "${cgpath}/memory.current" 2>/dev/null || echo "N/A"
    else
        $PODMAN_CMD top "$CONTAINER_NAME" o 2>/dev/null | awk 'NR>1 {sum+=$6} END {printf "%.0f MB", sum/1024}' || echo "N/A"
    fi
}

IDLE_RSS=$(get_container_rss)
echo "Container RSS (idle): ${IDLE_RSS}"
AVAIL_BEFORE=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
echo "Host RAM available  : ${AVAIL_BEFORE} MB"
echo ""

# ── 4. Healthcheck & latency ───────────────────────────────
echo -e "${YELLOW}[4/5] Healthcheck & Latency${NC}"
echo "---"
for i in 1 2 3; do
    LATENCY=$(curl -s -o /dev/null -w "%{time_total}s" --max-time 5 "${HEALTH_ENDPOINT}" 2>/dev/null || echo "FAIL")
    echo "  Healthcheck #$i: ${LATENCY}"
done
API_LATENCY=$(curl -s -o /dev/null -w "%{time_total}s" --max-time 10 "http://localhost:20130/api/v1/models" 2>/dev/null || echo "FAIL")
echo "  /api/v1/models    : ${API_LATENCY}"
echo ""

# ── 5. Load test ────────────────────────────────────────────
echo -e "${YELLOW}[5/5] Load Test (${BENCH_DURATION_SEC}s)${NC}"
echo "---"
echo "Sending concurrent requests to /api/v1/models ..."
AVAIL_BEFORE_LOAD=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
LOAD_START=$(date +%s)
for i in $(seq 1 10); do
    curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" \
        --max-time 15 "http://localhost:20130/api/v1/models" &
done
wait
LOAD_END=$(date +%s)
ELAPSED=$((LOAD_END - LOAD_START))
AVAIL_AFTER_LOAD=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
RAM_DELTA=$((AVAIL_BEFORE_LOAD - AVAIL_AFTER_LOAD))

echo "  Duration     : ~${ELAPSED}s"
echo "  RAM delta    : ${RAM_DELTA} KB ($(( RAM_DELTA / 1024 )) MB)"
echo "  Container RSS: $(get_container_rss)"
echo ""

# ── Summary ────────────────────────────────────────────────
echo "========================================"
echo "  Benchmark Complete"
echo "========================================"
echo ""
echo -e "${GREEN}Expected idle RSS on ARM64 TV Box (2GB RAM):${NC}"
echo "  Node.js 22 + Next standalone : ~150-220 MB"
echo "  With 5-10 concurrent requests: ~200-300 MB peak"
echo "  With NODE_OPTIONS max-old-space-size=512: safe ceiling"
echo ""
echo -e "${YELLOW}Red flags (investigate if seen):${NC}"
echo "  - Idle RSS > 400 MB"
echo "  - RAM delta > 200 MB after load test"
echo "  - Healthcheck latency > 2s"
echo "  - Container OOM killed (check: journalctl --user -u 9router -p err)"
echo ""
