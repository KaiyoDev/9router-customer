/**
 * StatusIndicator — dot + label component used across the page.
 */
import { getStatusColor, getStatusLabel } from "../lib/statusHelpers";

/**
 * @param {'operational'|'degraded'|'outage'|'unknown'} status
 * @param {string} [label] optional override label
 */
export default function StatusIndicator({ status, label }) {
  const textLabel = label ?? getStatusLabel(status);
  return (
    <span className="inline-flex items-center gap-1.5 text-xs font-medium">
      <span className={`w-1.5 h-1.5 rounded-full ${getStatusColor(status)}`} />
      <span className={getStatusColor(status).replace("bg-", "text-")}>{textLabel}</span>
    </span>
  );
}
