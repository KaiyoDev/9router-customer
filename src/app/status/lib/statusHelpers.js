/**
 * Shared helpers for status indicators and colors.
 */

/**
 * @param {'operational'|'degraded'|'outage'|'unknown'} status
 * @returns {string} Tailwind CSS bg class
 */
export function getStatusColor(status) {
  switch (status) {
    case "operational":
      return "bg-success";
    case "degraded":
      return "bg-warning";
    case "outage":
      return "bg-danger";
    default:
      return "bg-text-subtle";
  }
}

/**
 * @param {'operational'|'degraded'|'outage'|'unknown'} status
 * @returns {string} Human-readable label
 */
export function getStatusLabel(status) {
  switch (status) {
    case "operational":
      return "All Systems Operational";
    case "degraded":
      return "Partial Outage";
    case "outage":
      return "Major Outage";
    default:
      return "Unable to Verify";
  }
}

/**
 * @param {'operational'|'degraded'|'outage'|'unknown'} status
 * @returns {string} Tailwind border class
 */
export function getComponentBorderColor(status) {
  switch (status) {
    case "operational":
      return "border-l-success";
    case "degraded":
      return "border-l-warning";
    case "outage":
      return "border-l-danger";
    default:
      return "border-l-text-subtle";
  }
}

/**
 * @param {'operational'|'degraded'|'outage'|'unknown'} status
 * @returns {string} Tailwind text class for status text
 */
export function getStatusTextColor(status) {
  switch (status) {
    case "operational":
      return "text-success";
    case "degraded":
      return "text-warning";
    case "outage":
      return "text-danger";
    default:
      return "text-text-subtle";
  }
}

/**
 * Uptime badge color
 */
export function getUptimeColor(pct) {
  if (pct >= 99.9) return "text-success";
  if (pct >= 99) return "text-warning";
  return "text-danger";
}
