# 9Router ARM64 — Custom Distribution

ARM64-optimized fork of [decolua/9router](https://github.com/decolua/9router) for low-RAM TV Box deployment.

## Architecture Target

| Item | Value |
|---|---|
| CPU | ARM64 / aarch64 (Amlogic/Meson SoC) |
| RAM | 1.9 GB total, ~1.4 GB available |
| OS | Ubuntu 26.04 LTS (kernel 6.18.40-meson64) |
| Runtime | Podman 5.7.0 (rootless, crun) |
| Node.js | 22 LTS (Alpine ARM64) |
| Port | 20130 |

## Directory Structure

```
├── production/              # ARM64 production layer (tracked in git)
│   ├── Containerfile        # Multi-stage Podman build (ARM64)
│   ├── .excludes            # Permanent removal rules (synced every update)
│   ├── .patches/            # Custom source patches
│   │   ├── 001-low-memory-mode.patch
│   │   ├── 002-next-config-tweaks.patch
│   │   └── 003-reduce-memory-usage.patch
│   ├── build-and-deploy.sh  # Build + healthcheck + switch + rollback
│   └── 9router.container    # Podman Quadlet definition
│
├── custom/                  # User-managed overlays (preserved across syncs)
│   └── config/              # Config files to overlay into repo root
│       └── .env.production  # Production env template
│
├── scripts/
│   ├── sync-upstream.sh     # Main upstream sync script
│   ├── deploy-production.sh # One-command deploy (uses sync + build)
│   └── benchmark-memory.sh  # RAM/CPU benchmark tool
│
└── (upstream 9router source — fetched, not committed)
```

## Core Principle: Three-Layer Isolation

```
┌─────────────────────────────────────────────┐
│  Layer 1: Upstream source (decoulua/9router) │  ← git fetch, never committed
├─────────────────────────────────────────────┤
│  Layer 2: Custom patches (.patches/)         │  ← your changes, survive sync
├─────────────────────────────────────────────┤
│  Layer 3: Exclusions (.excludes)             │  ← permanent removals, survive sync
└─────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────┐
│  Layer 4: Persistent config (custom/config/) │  ← user secrets, never in git
├─────────────────────────────────────────────┤
│  Layer 5: Persistent data (~/.local/share/9router-data) │ ← DB + logs
└─────────────────────────────────────────────┘
```

## Quick Start

### First deployment

```bash
# 1. Clone your fork (not the upstream directly)
git clone https://github.com/YOU/9router.git
cd 9router
git checkout -b custom-arm64

# 2. Add upstream remote
git remote add upstream https://github.com/decolua/9router.git

# 3. Enable linger for auto-start on reboot
sudo loginctl enable-linger kaiyo

# 4. Deploy (builds image, healthchecks, starts container)
bash scripts/deploy-production.sh
```

### Updating from upstream

```bash
# Preview what would change (dry-run, no modifications)
bash scripts/sync-upstream.sh

# Apply patches and exclusions (modifies working tree)
bash scripts/sync-upstream.sh --apply

# Full cycle: sync → build → healthcheck → deploy → rollback-safe
bash scripts/sync-upstream.sh --build
```

### Rollback

```bash
# Revert to previous image (keeps data intact)
bash production/build-and-deploy.sh --rollback

# Or manually
podman stop 9router && podman rm 9router
# Edit ~/.config/containers/systemd/9router.container → change Image= line
systemctl --user daemon-reload && systemctl --user restart 9router
```

## Upstream Sync Mechanism

The sync script (`scripts/sync-upstream.sh`) implements a safe three-phase workflow:

### Phase 1: Fetch & Detect
```
git fetch upstream --prune
git diff HEAD..upstream/custom-arm64 --stat
```
Shows exactly what upstream changed. No modifications to your tree.

### Phase 2: Apply Exclusions (idempotent)
```bash
# Every sync run removes these permanently
while read pattern; do
    find . -path "$pattern" -delete
done < production/.excludes
```
If upstream re-introduces `Dockerfile` or `tests/`, they're stripped immediately.

### Phase 3: Apply Patches (conflict-aware)
```bash
for patch in production/.patches/*.patch; do
    git apply --check "$patch"   # detect conflicts first
    git apply --reject "$patch"  # apply, create .rej for conflicts
done
```
Conflicts are flagged clearly — you review `.rej` files before committing.

### Conflict Detection
The script checks each patch against the upstream diff:
- If upstream modified a line your patch also touches → **warning + .rej file**
- If upstream deleted a file your patch modifies → **warning + manual review**
- Non-conflicting patches apply cleanly

## Production Build Pipeline

```
Branch: custom-arm64
    │
    ├─ git fetch upstream           # get new commits
    │
    ├─ .excludes applied            # strip Docker/tests/docs/etc.
    │
    ├─ .patches/ applied            # inject ARM64 optimizations
    │
    ├─ production/Containerfile     # build ARM64 image
    │     ↓
    │  podman build --platform linux/arm64
    │     ↓
    │  Image tag: localhost/9router:<sha>-<date>
    │
    ├─ Healthcheck container        # verify it starts and responds
    │     ↓ pass?
    │
    ├─ Update Quadlet image tag     # point service to new image
    │
    ├─ systemctl --user restart     # swap to new image
    │     ↓ fail?
    │
    └─ Rollback to previous image   # automatic safety net
```

## Memory Optimization Details

| Setting | Default | ARM64 TV Box | Reason |
|---|---|---|---|
| `LOW_MEMORY_MODE` | off | **on** | Enables aggressive savings |
| Session TTL | 2h | 30min | TV Box = single session |
| Usage ring buffer | 50 entries | **20 entries** | Less in-memory history |
| Connection cache TTL | 30s | **15s** | Faster stale cleanup |
| V8 heap ceiling | unlimited | **512 MB** | Hard limit, prevents OOM |
| Request logging | on | **off** | Saves disk I/O + space |
| Cloud observability | on | **off** | Removes background network |

**Expected RAM usage:**
- Idle: ~150–220 MB RSS
- With requests: ~200–300 MB peak
- Safe headroom: ~800 MB (of 1.4 GB available)

## Management Commands

```bash
# Service control
systemctl --user status 9router
systemctl --user start  9router
systemctl --user stop   9router
systemctl --user restart 9router

# Logs
journalctl --user -u 9router -f          # live logs
journalctl --user -u 9router -n 100      # last 100 lines

# Container
podman ps --filter name=9router
podman logs 9router
podman images localhost/9router          # list image history

# Benchmark
bash scripts/benchmark-memory.sh
```

## Key Differences from Upstream

| Feature | Upstream | This Distribution |
|---|---|---|
| Container runtime | Docker / Docker Compose | **Podman + Quadlet** |
| Base image | node:22-alpine (any arch) | **node:22-alpine (ARM64)** |
| SQLite driver | fallback chain | **node:sqlite (native, Node 22)** |
| Memory limits | none | **V8 512MB + cgroup 1800MB** |
| Request logging | configurable | **disabled by default** |
| Upstream sync | manual | **automated with conflict detection** |
| Rollback | manual | **image-tag based, one command** |
| Excluded files | none | **Docker/CI/tests/docs stripped** |

## Security Notes

- Container runs as **non-root** (`nodejs` user, uid 1000)
- **Rootless Podman** — no sudo required
- No `privileged` mode, no host networking, no host PID/IPC
- `PrivateNetwork=true` in Quadlet (isolated network namespace)
- `ProtectSystem=strict` — read-only except `/app/data`
- Data volume mounted with `:Z` label (SELinux compatible)

## Troubleshooting

```bash
# Container won't start
journalctl --user -u 9router -n 50 --no-pager

# OOM killed
journalctl --user -u 9router -p err | grep -i oom

# Check current memory
podman stats 9router
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/9router.scope/memory.current

# Reset everything
systemctl --user stop 9router
podman rm 9router
bash scripts/deploy-production.sh

# Sync failed due to conflict
ls production/.patches/*.rej  # review rejected hunks
git diff                       # see what upstream changed
```
