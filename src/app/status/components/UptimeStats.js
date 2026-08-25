/**
 * UptimeStats — uptime percentages across time windows.
 */
import { getUptimeColor } from "../lib/statusHelpers";

export default function UptimeStats({ uptime, dailyBars }) {
  const periods = [
    { key: "24h", label: "24 Hours" },
    { key: "7d", label: "7 Days" },
    { key: "30d", label: "30 Days" },
  ];

  return (
    <div className="rounded-xl border border-border bg-surface p-5">
      <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted mb-4">
        Uptime
      </h3>
      <div className="grid grid-cols-3 gap-4">
        {periods.map(({ key, label }) => {
          const pct = uptime?.[key] ?? 100;
          const color = getUptimeColor(pct);
          return (
            <div key={key} className="text-center">
              <div className={`text-2xl font-semibold tabular-nums ${color}`}>
                {pct.toFixed(2)}%
              </div>
              <div className="text-xs text-text-subtle mt-1">{label}</div>
              {/* mini bar */}
              <div className="mt-2 h-1 w-full bg-border-subtle rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full ${color.replace("text-", "bg-")}`}
                  style={{ width: `${Math.min(pct, 100)}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>
      {/* Full-width uptime bar */}
      {dailyBars && dailyBars.length > 0 && (
        <div className="mt-4">
          <div className="text-xs text-text-subtle mb-1.5">30-day uptime</div>
          <div className="flex gap-px h-2">
            {dailyBars.map((day, i) => (
              <div
                key={i}
                className={`flex-1 rounded-sm ${
                  day >= 99.9 ? "bg-success" : day >= 99 ? "bg-warning" : "bg-danger"
                }`}
                title={`Day ${i + 1}: ~${day.toFixed(2)}%`}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
