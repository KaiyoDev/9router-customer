# 9Router Status Page — Custom Overlay

## Overview

A standalone status dashboard at **`/status`**, modelled after
[status.claude.com](https://status.claude.ai) and [status.vercel.com](https://vercel.com/status).
Completely isolated from the 9Router dashboard — upstream changes to
routing, providers, auth, or the dashboard UI **cannot** break it.

## File Map

```
src/app/status/                  ← everything below is custom
├── layout.js                    ← minimal layout (no sidebar)
├── page.js                      ← main page (client component)
├── components/
│   ├── StatusHeader.js          ← top bar + theme toggle
│   ├── OverallStatusCard.js     ← big hero card
│   ├── ServiceStatus.js         ← core services list
│   ├── ProviderGrid.js          ← per-provider status
│   ├── UptimeStats.js           ← 24h / 7d / 30d uptime
│   ├── UsageStats.js            ← request volume + latency chart
│   ├── IncidentTimeline.js      ← incident history
│   ├── MaintenanceBanner.js     ← maintenance notice
│   └── LastUpdated.js           ← timestamp footer
├── hooks/
│   └── useStatusData.js         ← fetch + 30s poll hook
└── lib/
    ├── types.js                 ← TypeScript-style JSDoc types
    ├── mockData.js              ← static fallback (MOCK_MODE flag)
    └── statusHelpers.js         ← color/label utilities
```

API routes (also custom, no upstream overlap):

```
src/app/api/status/
├── route.js          ← /api/status — aggregated health
└── providers/
    └── route.js      ← /api/status/providers — per-provider list
```

## How It Works

### Data Flow

```
/api/status  ──→  fetches /api/health, /api/version, /api/auth/status,
                    /api/providers, /api/usage/stats
                └─→ combines into one StatusData object

/api/status/providers  ──→  reads SQLite provider connections
                             → normalised per-provider status list

Frontend (useStatusData)  ──→  polls /api/status every 30s
                                falls back to mockData.js on error
```

### Upstream Safety

| Concern | Solution |
|---|---|
| Dashboard UI changes | Status lives in its own `src/app/status/` tree — never touches `src/app/(dashboard)/` |
| New API routes added upstream | Status API only reads existing endpoints; new routes are ignored unless wired in |
| Provider registry changes | `/api/status/providers` reads from DB directly, not from upstream registry files |
| Component refactor | All status components are self-contained; no imports from dashboard code |
| Mock mode | `MOCK_MODE = true` in `lib/mockData.js` for CI/offline testing |

## Adding a New Service Component

1. Add to `components` array in `src/app/api/status/route.js` → `buildComponentStatuses()`
2. Add corresponding row in `MOCK_STATUS.components` in `lib/mockData.js`
3. That's it — `ServiceStatus.js` renders anything in the array automatically

## Adding a New Provider

1. Add provider ID to `DISPLAY_PROVIDERS` set in `src/app/api/status/providers/route.js`
2. Add entry to `MOCK_PROVIDERS` in `lib/mockData.js`
3. The grid auto-renders based on API response

## Switching API Source

The adapter pattern is in `src/app/status/lib/mockData.js`:

```js
// lib/mockData.js
export const MOCK_MODE = false;  // true = always use mocks, false = real API only
```

To wire a different data source, edit `useStatusData.js` — the hook already
fetches from `/api/status`. No UI changes needed.

## Running Locally

```bash
# from repo root
npm run dev
# then open http://localhost:20127/status
```

## Deployment

Same as the rest of 9Router — the `/status` route is part of the
Next.js standalone output and ships automatically with the Containerfile.
No extra config needed.

## Upstream Update Checklist

When pulling from upstream 9Router, verify:

1. `git pull origin master` (or your upstream remote)
2. `git diff --name-only` — check no status/ files are touched
3. If upstream adds a conflicting route like `/status`, update
   `next.config.mjs` rewrites to prioritise the status route
4. Run tests: `npm run build` to confirm nothing breaks

The status page is protected by the `.excludes` system during sync —
it will never be overwritten by an upstream patch.
