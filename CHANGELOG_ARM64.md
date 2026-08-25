# 9Router ARM64 Distribution — Change Log

## [2025-01-15] v1.0.0 — Initial ARM64 Distribution

### Architecture
- Target platform: ARM64 / aarch64 (Amlogic/Meson SoC TV Box)
- OS: Ubuntu 26.04 LTS (kernel 6.18.40-meson64)
- Container runtime: Podman 5.7.0 (rootless, crun)
- No Docker, no docker-compose, no Kubernetes

### Features
- **Upstream sync mechanism** (`scripts/sync-upstream.sh`)
  - Fetch from `decolua/9router` without overwriting custom changes
  - Conflict detection between patches and upstream
  - Permanent exclusion of Docker/CI/tests/docs
  - Backup branch on every sync
- **Multi-stage ARM64 Containerfile** (`production/Containerfile`)
  - Node.js 22 Alpine ARM64 (native `node:sqlite`)
  - `--max-old-space-size=512` V8 heap limit
  - Non-root `nodejs` user
  - Healthcheck via HTTP `/api/auth/status`
- **Podman Quadlet** (`production/9router.container`)
  - MemoryMax=1800M, PrivateNetwork=true
  - Persistent volumes for DB + usage logs
  - Auto-restart with systemd
- **Build & deploy pipeline** (`production/build-and-deploy.sh`)
  - Image tagged by git SHA + date (rollback-safe)
  - Healthcheck before switching to new image
  - Automatic rollback on failure
- **Low-memory patches** (`production/.patches/`)
  - Reduced session TTL (2h → 30min)
  - Reduced ring buffer (50 → 20 entries)
  - Reduced connection cache TTL (30s → 15s)
  - `LOW_MEMORY_MODE` environment toggle
- **Permanent exclusions** (`production/.excludes`)
  - Docker/docker-compose/K8s files
  - CI/CD workflows
  - Documentation translations
  - Test suites & baselines
  - CLI package
  - Development tooling

### Expected RAM Usage
| State | RSS |
|---|---|
| Idle | ~150–220 MB |
| With requests | ~200–300 MB peak |
| Headroom | ~800 MB (of 1.4 GB available) |

### Directory Structure
```
production/        — ARM64 production layer (tracked)
custom/            — User-managed overlays (preserved)
scripts/           — Sync, deploy, benchmark
├── sync-upstream.sh
├── deploy-production.sh
└── benchmark-memory.sh
```
