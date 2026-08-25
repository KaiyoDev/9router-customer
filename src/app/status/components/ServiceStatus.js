/**
 * ServiceStatus — list of core service components with status.
 */
import { getComponentBorderColor, getStatusColor } from "../lib/statusHelpers";
import StatusIndicator from "./StatusIndicator";

export default function ServiceStatus({ components }) {
  return (
    <div className="rounded-xl border border-border bg-surface overflow-hidden">
      <div className="px-5 py-3 border-b border-border-subtle flex items-center justify-between">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-text-muted">
          Core Services
        </h3>
        <span className="text-xs text-text-subtle">{components.length} services</span>
      </div>
      <div className="divide-y divide-border-subtle">
        {components.map((comp) => (
          <div
            key={comp.id}
            className={`flex items-center justify-between px-5 py-3 border-l-2 ${getComponentBorderColor(comp.status)} hover:bg-bg-alt transition-colors`}
          >
            <div className="flex items-center gap-3">
              <span className={`w-2 h-2 rounded-full shrink-0 ${getStatusColor(comp.status)}`} />
              <div>
                <span className="text-sm font-medium text-text-main">{comp.name}</span>
                <span className="text-xs text-text-subtle ml-2">{comp.description}</span>
              </div>
            </div>
            <StatusIndicator status={comp.status} />
          </div>
        ))}
      </div>
    </div>
  );
}
