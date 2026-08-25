/**
 * UsageStats — request volume and latency metrics.
 */
export default function UsageStats({ usage }) {
  return (
    <div className="rounded-xl border border-border bg-surface p-5">
      <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted mb-4">
        Usage &amp; Latency
      </h3>

      {/* Request count */}
      <div className="flex items-end justify-between mb-4">
        <div>
          <div className="text-2xl font-semibold text-text-main tabular-nums">
            {formatNumber(usage?.requests24h ?? 0)}
          </div>
          <div className="text-xs text-text-subtle mt-0.5">Requests in last 24h</div>
        </div>
        {usage?.requestChange && (
          <span
            className={`text-xs font-medium px-2 py-1 rounded-full ${
              usage.requestChange.startsWith("+")
                ? "bg-success/10 text-success"
                : "bg-danger/10 text-danger"
            }`}
          >
            {usage.requestChange} vs prior
          </span>
        )}
      </div>

      {/* Placeholder latency note */}
      <div className="text-xs text-text-subtle border-t border-border-subtle pt-3">
        Latency monitoring enabled when health probes are configured.
      </div>
    </div>
  );
}

function formatNumber(n) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return n.toString();
}
