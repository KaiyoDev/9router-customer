/**
 * MaintenanceBanner — shows upcoming or ongoing maintenance window.
 */
export default function MaintenanceBanner({ maintenance }) {
  if (!maintenance) return null;

  return (
    <div
      className={`rounded-xl border px-5 py-3 flex items-start gap-3 ${
        maintenance.ongoing
          ? "border-warning/30 bg-warning/5"
          : "border-info/30 bg-info/5"
      }`}
    >
      <span className="text-lg shrink-0">{maintenance.ongoing ? "🔧" : "📅"}</span>
      <div>
        <div className="text-sm font-medium">
          {maintenance.ongoing ? "Maintenance in progress" : "Scheduled maintenance"}
        </div>
        <div className="text-xs text-text-muted mt-0.5">{maintenance.description}</div>
        <div className="text-xs text-text-subtle mt-1">
          Scheduled: {new Date(maintenance.scheduledAt).toLocaleString()}
        </div>
      </div>
    </div>
  );
}
