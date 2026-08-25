/**
 * OverallStatusCard — big hero card showing current system status.
 */
"use client";

import { getStatusColor, getStatusLabel } from "./StatusIndicator";

export default function OverallStatusCard({ status, version, updatedAt }) {
  const color = getStatusColor(status);
  const label = getStatusLabel(status);

  return (
    <div className="rounded-xl border border-border bg-surface p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-4">
          <span className={`inline-block w-3 h-3 rounded-full ${color} ring-2 ring-offset-2 ring-offset-bg ${color.replace("bg-", "ring-")}`} />
          <div>
            <h2 className="text-lg font-semibold text-text-main">{label}</h2>
            <p className="text-sm text-text-muted mt-0.5">
              All systems operational · v{version}
            </p>
          </div>
        </div>
        <div className="text-right text-xs text-text-subtle shrink-0">
          <div>Last updated</div>
          <div className="font-mono mt-0.5">{formatRelative(updatedAt)}</div>
        </div>
      </div>
    </div>
  );
}

function formatRelative(isoStr) {
  if (!isoStr) return "just now";
  const diff = Date.now() - new Date(isoStr).getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}
