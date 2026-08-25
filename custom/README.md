# 9Router ARM64 Custom Config
#
# This directory holds configuration that must survive upstream syncs.
# Files here are COPIED (not merged) into the production build root.
#
# Structure:
#   custom/config/<path>  →  <path>  (at repo root, after sync)
#
# Example:
#   custom/config/.env.production  →  .env.production
#
# NOTE: Do NOT put secrets here if this repo is public.
#       Use the host's ~/.config/9router-arm64/ instead.

# To add a custom config file, create it here with the target path as filename.
# For example, to customize .env.production:
#   mkdir -p custom/config
#   cp .env.example custom/config/.env.production
#   # Then edit custom/config/.env.production
