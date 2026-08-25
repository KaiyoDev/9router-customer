/**
 * ProviderGrid — per-provider status cards.
 */
import { getComponentBorderColor, getStatusColor } from "../lib/statusHelpers";

const CATEGORY_LABELS = {
  api: "API Key",
  oauth: "OAuth",
  free: "Free Tier",
  webCookie: "Web Cookie",
  other: "Other",
};

export default function ProviderGrid({ providers }) {
  if (!providers || providers.length === 0) {
    return (
      <div className="rounded-xl border border-border bg-surface p-8 text-center text-sm text-text-subtle">
        No provider connections configured yet.
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-surface overflow-hidden">
      <div className="px-5 py-3 border-b border-border-subtle flex items-center justify-between">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted">
          Provider Status
        </h3>
        <span className="text-xs text-text-subtle">
          {providers.filter((p) => p.status === "operational").length}/{providers.length} operational
        </span>
      </div>
      <div className="divide-y divide-border-subtle">
        {providers.map((p) => (
          <div
            key={p.id}
            className={`flex items-center justify-between px-5 py-3 border-l-2 ${getComponentBorderColor(p.status)} hover:bg-bg-alt transition-colors`}
          >
            <div className="flex items-center gap-3">
              <span className={`w-2 h-2 rounded-full shrink-0 ${getStatusColor(p.status)}`} />
              <div>
                <span className="text-sm font-medium text-text-main">{p.name}</span>
                <span className="text-xs text-text-subtle ml-2">
                  · {CATEGORY_LABELS[p.category] ?? p.category}
                </span>
              </div>
            </div>
            <div className="flex items-center gap-4">
              <span className="text-xs text-text-subtle tabular-nums">
                {p.activeConnections}/{p.connections} active
              </span>
              <span className={`text-xs font-medium ${getStatusColor(p.status).replace("bg-", "text-")}`}>
                {p.status === "operational" ? "Operational" : p.status === "degraded" ? "Degraded" : "Unknown"}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
