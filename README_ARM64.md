# 9Router ARM64 — README

## Overview

This is a **custom ARM64-optimized distribution** of [decolua/9router](https://github.com/decolua/9router), designed for low-RAM TV Box deployment on Ubuntu 26.04 LTS (aarch64) with Podman + Quadlet + systemd.

### What's Different from Upstream

| Feature | Upstream | This Distribution |
|---|---|---|
| Container Runtime | Docker / Docker Compose | **Podman + Quadlet** |
| Base Image | Multi-arch | **ARM64 only (linux/arm64)** |
| SQLite Driver | fallback chain | **node:sqlite (Node 22 native)** |
| Memory Limits | None | **V8 512MB + cgroup 1800MB** |
| Request Logging | Configurable | **Disabled by default** |
| Upstream Sync | Manual | **Automated with conflict detection** |
| Rollback | Manual | **Image-tag based, one command** |
| Excluded Files | None | **Docker/CI/tests/docs stripped** |

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Layer 1: Upstream source (decolua/9router)               │  ← git fetch
├──────────────────────────────────────────────────────────┤
│  Layer 2: Custom patches (.patches/)                      │  ← your changes
├──────────────────────────────────────────────────────────┤
│  Layer 3: Exclusions (.excludes)                          │  ← permanent removals
├──────────────────────────────────────────────────────────┤
│  Layer 4: Production build (production/)                  │  ← Containerfile
├──────────────────────────────────────────────────────────┤
│  Layer 5: Persistent config (custom/config/)              │  ← user secrets
├──────────────────────────────────────────────────────────┤
│  Layer 6: Persistent data (~/.local/share/9router-data)   │  ← DB + logs
└──────────────────────────────────────────────────────────┘
```

## Quick Start

### First-time Setup

```bash
# 1. Clone your fork (not upstream directly)
git clone https://github.com/YOU/9router.git
cd 9router
git checkout -b custom-arm64

# 2. Add upstream remote
git remote add upstream https://github.com/decolua/9router.git

# 3. On the TV Box — enable linger for auto-start
sudo loginctl enable-linger kaiyo

# 4. Deploy (full pipeline: sync → build → deploy)
bash scripts/deploy-production.sh
```

### Routine Updates

```bash
# Preview what upstream changed (no modifications)
bash scripts/sync-upstream.sh

# Apply upstream + patches + exclusions
bash scripts/sync-upstream.sh --apply

# Full pipeline: sync + build + healthcheck + deploy
bash scripts/sync-upstream.sh --build

# Or with make
make sync          # preview
make sync-apply    # apply
make deploy        # full pipeline
```

### Rollback

```bash
# Revert to previous image (keeps data intact)
bash production/build-and-deploy.sh --rollback
```

## Directory Structure

```
├── production/                  # ARM64 production layer (tracked)
│   ├── Containerfile            # Multi-stage Podman build
│   ├── .excludes                # Permanent removal rules
│   ├── .patches/                # Custom source patches
│   │   ├── 001-low-memory-mode.patch
│   │   ├── 002-next-config-tweaks.patch
│   │   └── 003-reduce-memory-usage.patch
│   ├── build-and-deploy.sh      # Build + healthcheck + switch
│   ├── 9router.container        # Podman Quadlet definition
│   └── README.md                # Detailed documentation
│
├── custom/                      # User-managed overlays (preserved)
│   └── config/                  # Config files to overlay
│       └── .env.production      # Production env template
│
├── scripts/
│   ├── sync-upstream.sh         # Main upstream sync script
│   ├── deploy-production.sh     # One-command deploy
│   └── benchmark-memory.sh      # RAM/CPU benchmark tool
│
├── Makefile                     # Convenience commands
├── package.json                 # Upstream root (unchanged)
└── ...                          # Upstream source (git-managed)
```

## Management Commands

```bash
# Service control
systemctl --user status  9router
systemctl --user start   9router
systemctl --user stop    9router
systemctl --user restart 9router

# Logs
journalctl --user -u 9router -f          # live logs
journalctl --user -u 9router -n 100      # last 100 lines

# Container
podman ps --filter name=9router
podman logs 9router
podman images localhost/9router          # image history

# Benchmark
bash scripts/benchmark-memory.sh
```

## RAM Budget (Host: 1.9 GB total)

```
Host RAM: 1.9 GB
├── OS + systemd:       ~300 MB
├── Available for app:  ~1.1 GB
│
├── Container (cgroup): MemoryMax=1800M
├── Node.js (V8):       max-old-space-size=512MB
│
└── Expected RSS:
    ├── Idle:           ~150–220 MB
    ├── With requests:  ~200–300 MB peak
    └── Safe margin:    ~800 MB headroom
```

## Key Optimizations

| Setting | Value | Purpose |
|---|---|---|
| `LOW_MEMORY_MODE=1` | env | Enables aggressive memory savings |
| Session TTL | 30 min | TV Box = single short session |
| Usage ring buffer | 20 entries | Less in-memory history |
| Connection cache TTL | 15s | Faster stale cleanup |
| V8 heap ceiling | 512 MB | Hard limit, prevents OOM |
| Request logging | off | Saves disk I/O + space |
| Cloud observability | off | Removes background network |

## Upstream Sync Mechanism

The sync script (`scripts/sync-upstream.sh`) implements a safe three-phase workflow:

1. **Fetch & Detect** — Shows what upstream changed without modifying anything
2. **Apply Exclusions** — Strips Docker/CI/tests/docs permanently via `.excludes`
3. **Apply Patches** — Injects ARM64 optimizations with conflict detection

Conflicts are flagged clearly — you review `.rej` files before committing.

## Security

- Container runs as **non-root** (`nodejs` user, uid 1000)
- **Rootless Podman** — no sudo required
- No `privileged` mode, no host networking, no host PID/IPC
- `PrivateNetwork=true` in Quadlet
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

# Sync failed due to conflict
ls production/.patches/*.rej  # review rejected hunks
git diff                       # see what upstream changed
```

## License

Same as upstream 9router (MIT).
