/**
 * /api/status/providers — Per-provider connection health summary.
 *
 * Returns a lightweight list of configured providers with their
 * current operational state (derived from configuration, not live pings).
 */
import { NextResponse } from "next/server";
import { getProviderConnections } from "@/lib/db";
import REGISTRY from "open-sse/providers/registry/index.js";

// Known LLM providers for status display
const DISPLAY_PROVIDERS = new Set([
  "anthropic",
  "openai",
  "gemini",
  "deepseek",
  "groq",
  "xai",
  "kiro",
  "cohere",
  "fireworks",
  "vertex",
  "azure",
  "ollama",
  "ollama-local",
  "openrouter",
  "mistral",
  "claude",
  "copilot",
  "cursor",
  "codex",
  "qoder",
  "opencode",
  "grok-cli",
  "grok-web",
]);

function getDisplayInfo(providerId) {
  const entry = REGISTRY.find((r) => r.id === providerId);
  if (!entry) return null;
  return {
    name: entry.uiAlias || entry.name || providerId,
    icon: entry.icon || null,
    category: entry.category || "other",
  };
}

export async function GET() {
  try {
    const connections = await getProviderConnections();
    const byProvider = {};

    for (const conn of connections) {
      const pid = conn.provider;
      if (!DISPLAY_PROVIDERS.has(pid)) continue;

      if (!byProvider[pid]) {
        const info = getDisplayInfo(pid);
        byProvider[pid] = {
          id: pid,
          name: info?.name || pid,
          category: info?.category || "other",
          connections: 0,
          activeConnections: 0,
          status: "unknown",
        };
      }

      byProvider[pid].connections += 1;
      if (conn.isActive !== false) byProvider[pid].activeConnections += 1;
    }

    // Derive status from active connections
    const items = Object.values(byProvider).map((p) => ({
      ...p,
      status:
        p.activeConnections > 0 ? "operational" : p.connections > 0 ? "degraded" : "unknown",
    }));

    // Sort: operational first, then degraded, then unknown
    const order = { operational: 0, degraded: 1, unknown: 2 };
    items.sort((a, b) => (order[a.status] ?? 2) - (order[b.status] ?? 2));

    return NextResponse.json({ providers: items });
  } catch (error) {
    console.error("[Status API] Failed to fetch providers:", error);
    return NextResponse.json({ providers: [] });
  }
}

export const dynamic = "force-dynamic";
