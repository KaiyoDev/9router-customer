# Quick Reference — 9Router ARM64

## Commands Cheat Sheet

```bash
# === First-time setup (on TV Box) ===
sudo loginctl enable-linger kaiyo           # required for auto-start on reboot
git clone https://github.com/YOU/9router.git
cd 9router && git checkout -b custom-arm64
git remote add upstream https://github.com/decolua/9router.git
bash scripts/deploy-production.sh           # full pipeline

# === Daily operations ===
make sync           # preview upstream changes
make sync-apply     # apply sync
make build          # build image only (dry-run)
make deploy         # full pipeline
make rollback       # revert to previous image
make bench          # run memory benchmark
make status         # check container & service
make logs           # follow live logs

# === Manual commands ===
bash scripts/sync-upstream.sh              # dry-run
bash scripts/sync-upstream.sh --apply      # apply changes
bash scripts/sync-upstream.sh --build      # sync + build + deploy
bash production/build-and-deploy.sh        # build + healthcheck + switch
bash production/build-and-deploy.sh --rollback  # revert image

# === Systemd management ===
systemctl --user status  9router
systemctl --user start   9router
systemctl --user stop    9router
systemctl --user restart 9router
journalctl --user -u 9router -f

# === Podman management ===
podman ps --filter name=9router
podman logs 9router
podman images localhost/9router
```

## File Locations

| What | Where |
|---|---|
| Production Containerfile | `production/Containerfile` |
| Quadlet definition | `production/9router.container` |
| Exclusion rules | `production/.excludes` |
| Custom patches | `production/.patches/*.patch` |
| Build script | `production/build-and-deploy.sh` |
| Sync script | `scripts/sync-upstream.sh` |
| Deploy script | `scripts/deploy-production.sh` |
| Benchmark script | `scripts/benchmark-memory.sh` |
| User config (local) | `~/.config/9router-arm64/env` |
| Persistent data | `~/.local/share/9router-data/` |
| Persistent logs | `~/.local/share/9router-logs/` |
| Quadlet file (installed) | `~/.config/containers/systemd/9router.container` |

## Image Tags

```
Format: localhost/9router:<git-sha>-<date>
Example: localhost/9router:a1b2c3d-20250115
```

Old images are kept for rollback. Use `podman images localhost/9router` to list them.

## Environment Variables

Copy `custom/config/.env.production` to host and edit secrets:
```bash
# On TV Box
mkdir -p ~/.config/9router-arm64
cp custom/config/.env.production ~/.config/9router-arm64/
# Edit with your secrets, then reference in Quadlet:
# EnvFile=/home/kaiyo/.config/9router-arm64/.env.production
```

Key variables:
- `JWT_SECRET` — session cookie secret (required)
- `INITIAL_PASSWORD` — default admin password (required)
- `LOW_MEMORY_MODE=1` — enable aggressive memory savings
- `ENABLE_REQUEST_LOGS=false` — disable request logging
- `OBSERVABILITY_ENABLED=false` — disable cloud sync

## Memory Budget (Host: 1.9 GB)

```
Idle:         ~150-220 MB
With requests: ~200-300 MB peak
Safe ceiling:  512 MB (V8) / 1800 MB (cgroup)
Headroom:      ~800 MB
```
