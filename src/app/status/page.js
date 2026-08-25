/**
 * Status Page — /status
 *
 * A clean, minimal status dashboard inspired by status.claude.com and
 * Vercel's status pages.  Completely isolated from the 9Router dashboard:
 *   • Own layout (no sidebar, no nav chrome)
 *   • Own API layer (/api/status, /api/status/providers)
 *   • Mock data fallback for offline/CI testing
 *
 * Upstream-safe: adding/updating any dashboard route, component, or
 * feature does NOT affect this page.
 */
"use client";

import { useStatusData, useProviderData } from "./hooks/useStatusData";
import StatusHeader from "./components/StatusHeader";
import OverallStatusCard from "./components/OverallStatusCard";
import ServiceStatus from "./components/ServiceStatus";
import ProviderGrid from "./components/ProviderGrid";
import UptimeStats from "./components/UptimeStats";
import IncidentTimeline from "./components/IncidentTimeline";
import UsageStats from "./components/UsageStats";
import MaintenanceBanner from "./components/MaintenanceBanner";
import LastUpdated from "./components/LastUpdated";
import { generateDailyUptimeBars } from "./lib/mockUptime";
import { MOCK_STATUS, MOCK_PROVIDERS } from "./lib/mockData";

export default function StatusPage() {
  const { data: status, loading: statusLoading } = useStatusData();
  const { providers: providerList, loading: providersLoading } = useProviderData();

  // ── resolve data (real > mock) ──────────────────────────────────────
  const data = status ?? MOCK_STATUS;
  const providers = providerList ?? MOCK_PROVIDERS;
  const dailyBars = generateDailyUptimeBars(30);

  return (
    <div className="min-h-screen bg-bg flex flex-col">
      {/* Header */}
      <StatusHeader />

      {/* Main content */}
      <main className="flex-1 w-full max-w-3xl mx-auto px-4 py-8 sm:px-6">
        {/* Maintenance banner (if any) */}
        {data.maintenance && <MaintenanceBanner maintenance={data.maintenance} />}

        {/* Overall status */}
        <div className="mt-6">
          {statusLoading ? (
            <SkeletonCard />
          ) : (
            <OverallStatusCard
              status={data.status}
              version={data.version}
              updatedAt={data.updatedAt}
            />
          )}
        </div>

        {/* Two-column grid: services + uptime */}
        <div className="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-4">
          {statusLoading ? (
            <>
              <SkeletonCard />
              <SkeletonCard />
            </>
          ) : (
            <>
              <ServiceStatus components={data.components} />
              <UptimeStats uptime={data.uptime} dailyBars={dailyBars} />
            </>
          )}
        </div>

        {/* Usage & latency */}
        <div className="mt-4">
          {statusLoading ? (
            <SkeletonCard />
          ) : (
            <UsageStats usage={data.usage} />
          )}
        </div>

        {/* Provider grid */}
        <div className="mt-4">
          {providersLoading ? (
            <SkeletonCard />
          ) : (
            <ProviderGrid providers={providers} />
          )}
        </div>

        {/* Incidents */}
        <div className="mt-4">
          {statusLoading ? (
            <SkeletonCard />
          ) : (
            <IncidentTimeline incidents={data.incidents} />
          )}
        </div>

        {/* Footer */}
        <LastUpdated updatedAt={data.updatedAt} />
      </main>

      {/* Branding footer */}
      <footer className="py-4 text-center text-xs text-text-subtle border-t border-border-subtle">
        <span>Powered by </span>
        <span className="font-medium text-text-muted">9Router</span>
        <span className="mx-1">·</span>
        <span>v{data.version}</span>
      </footer>
    </div>
  );
}

/** Minimal skeleton placeholder used while data loads */
function SkeletonCard() {
  return (
    <div className="rounded-xl border border-border bg-surface p-5 animate-pulse">
      <div className="h-4 bg-border-subtle rounded w-1/3 mb-4" />
      <div className="space-y-3">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="flex items-center gap-3">
            <div className="w-2 h-2 bg-border-subtle rounded-full" />
            <div className="h-3 bg-border-subtle rounded w-2/3" />
          </div>
        ))}
      </div>
    </div>
  );
}
