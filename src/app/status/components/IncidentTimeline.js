/**
 * IncidentTimeline — chronological list of recent incidents.
 */
import { getStatusColor } from "../lib/statusHelpers";

const SEVERITY_ICON = {
  minor: "info",
  major: "warning",
  critical: "danger",
};

export default function IncidentTimeline({ incidents }) {
  if (!incidents || incidents.length === 0) {
    return (
      <div className="rounded-xl border border-border bg-surface p-6 text-center">
        <div className="text-sm text-text-muted">No recent incidents.</div>
        <div className="text-xs text-text-subtle mt-1">All systems have been stable.</div>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-surface overflow-hidden">
      <div className="px-5 py-3 border-b border-border-subtle">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted">
          Recent Incidents
        </h3>
      </div>
      <div className="divide-y divide-border-subtle">
        {incidents.map((inc) => (
          <div key={inc.id} className="px-5 py-3 flex gap-3">
            <div className="shrink-0 mt-0.5">
              <span
                className={`inline-block w-2 h-2 rounded-full ${
                  inc.resolvedAt ? "bg-success" : "bg-danger animate-pulse"
                }`}
              />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-sm font-medium text-text-main">{inc.title}</span>
                <span
                  className={`text-xs px-1.5 py-0.5 rounded font-medium ${
                    inc.resolvedAt
                      ? "bg-success/10 text-success"
                      : "bg-danger/10 text-danger"
                  }`}
                >
                  {inc.resolvedAt ? "Resolved" : "Active"}
                </span>
              </div>
              <p className="text-xs text-text-muted mt-0.5 line-clamp-2">{inc.description}</p>
              <div className="text-xs text-text-subtle mt-1">
                {formatDate(inc.date)}
                {inc.resolvedAt && ` · Resolved ${formatDate(inc.resolvedAt)}`}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function formatDate(isoStr) {
  if (!isoStr) return "";
  const d = new Date(isoStr);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}
