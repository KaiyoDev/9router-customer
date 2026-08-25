# ============================================================
# 9Router ARM64 — Production Makefile
# Quick commands for daily operations on the TV Box
# ============================================================

.PHONY: help sync sync-apply build deploy rollback bench clean status logs

help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════╗"
	@echo "║     9Router ARM64 — Production Commands          ║"
	@echo "╚══════════════════════════════════════════════════╝"
	@echo ""
	@echo "  make sync          Preview upstream changes (dry-run)"
	@echo "  make sync-apply    Apply upstream + patches + exclusions"
	@echo "  make build         Build Podman image (no deploy)"
	@echo "  make deploy        Full: sync → build → healthcheck → deploy"
	@echo "  make rollback      Revert to previous image"
	@echo "  make bench         Run RAM/CPU benchmark"
	@echo "  make status        Check container & service status"
	@echo "  make logs          Follow live logs"
	@echo "  make clean         Remove .next and build artifacts"
	@echo ""

sync:
	bash scripts/sync-upstream.sh

sync-apply:
	bash scripts/sync-upstream.sh --apply

build:
	bash production/build-and-deploy.sh --dry-run

deploy:
	bash scripts/deploy-production.sh

rollback:
	bash production/build-and-deploy.sh --rollback

bench:
	bash scripts/benchmark-memory.sh

status:
	@echo "=== Service ===" && systemctl --user status 9router --no-pager | head -8
	@echo "" && echo "=== Container ===" && podman ps --filter name=9router --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo "" && echo "=== Images ===" && podman images localhost/9router --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

logs:
	journalctl --user -u 9router -f

clean:
	rm -rf .next .next-cli-build .next-analyze/*
	rm -rf node_modules/.cache/*
	echo "Cleaned build artifacts"
