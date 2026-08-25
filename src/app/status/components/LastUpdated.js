/**
 * LastUpdated — timestamp display at the bottom of the page.
 */
export default function LastUpdated({ updatedAt }) {
  return (
    <div className="text-center text-xs text-text-subtle py-4">
      <span>Last updated </span>
      <time dateTime={updatedAt} className="font-mono">
        {formatRelative(updatedAt)}
      </time>
      <span className="mx-1">·</span>
      <span>Monitored every 30s</span>
    </div>
  );
}

function formatRelative(isoStr) {
  if (!isoStr) return "just now";
  const diff = Date.now() - new Date(isoStr).getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ${mins % 60}m ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}
