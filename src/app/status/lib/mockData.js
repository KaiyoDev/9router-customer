/**
 * Mock data layer for the Status page.
 *
 * Used when the server has no real data (fresh install, DB not ready).
 * Swap `MOCK_MODE = false` to force real API calls only.
 */
export const MOCK_MODE = true;

/** @type {import('./types').StatusData} */
export const MOCK_STATUS = {
  name: "9Router",
  version: "0.5.55",
  url: "",
  status: "operational",
  uptime: { "24h": 99.98, "7d": 99.95, "30d": 99.91 },
  components: [
    { id: "api", name: "API", status: "operational", description: "Core routing engine & REST API" },
    { id: "dashboard", name: "Dashboard", status: "operational", description: "Web management interface" },
    { id: "auth", name: "Authentication", status: "operational", description: "Password + SSO gateways" },
    { id: "providers", name: "Provider Connections", status: "operational", description: "12 providers configured" },
    { id: "database", name: "Database", status: "operational", description: "SQLite persistence layer" },
    { id: "tunnel", name: "Tunnel Service", status: "unknown", description: "Cloudflare/Tailscale tunnel" },
  ],
  providers: {
    configured: 12,
    active: 10,
    categoryBreakdown: { api: 8, free: 2, oauth: 2 },
  },
  usage: { requests24h: 48230, requestChange: "+3.2%" },
  incidents: [
    {
      id: "inc-1",
      date: "2026-08-23",
      title: "Provider latency spike",
      description: "Intermittent slow responses from Groq API (~2.1s avg → ~800ms)",
      severity: "minor",
      resolvedAt: "2026-08-23T14:30:00Z",
    },
    {
      id: "inc-2",
      date: "2026-08-20",
      title: "Dashboard session timeout",
      description: "JWT expiry reduced session duration from 24h to 1h unexpectedly",
      severity: "major",
      resolvedAt: "2026-08-20T09:15:00Z",
    },
  ],
  maintenance: null,
  updatedAt: new Date().toISOString(),
};

/** @type {import('./types').ProviderStatus[]} */
export const MOCK_PROVIDERS = [
  { id: "openai", name: "OpenAI", category: "api", connections: 3, activeConnections: 3, status: "operational" },
  { id: "anthropic", name: "Anthropic", category: "api", connections: 2, activeConnections: 2, status: "operational" },
  { id: "gemini", name: "Google Gemini", category: "api", connections: 2, activeConnections: 2, status: "operational" },
  { id: "deepseek", name: "DeepSeek", category: "api", connections: 2, activeConnections: 2, status: "operational" },
  { id: "groq", name: "Groq", category: "api", connections: 1, activeConnections: 1, status: "operational" },
  { id: "xai", name: "xAI (Grok)", category: "api", connections: 1, activeConnections: 1, status: "operational" },
  { id: "kiro", name: "Kiro", category: "oauth", connections: 1, activeConnections: 1, status: "degraded" },
  { id: "mistral", name: "Mistral", category: "api", connections: 1, activeConnections: 1, status: "operational" },
  { id: "ollama", name: "Ollama", category: "api", connections: 1, activeConnections: 1, status: "operational" },
  { id: "cohere", name: "Cohere", category: "api", connections: 1, activeConnections: 0, status: "degraded" },
  { id: "vertex", name: "Vertex AI", category: "oauth", connections: 1, activeConnections: 1, status: "operational" },
  { id: "openrouter", name: "OpenRouter", category: "api", connections: 1, activeConnections: 1, status: "operational" },
];

/** @type {Array<{hour:number,latency:number}>} */
export const MOCK_LATENCY = Array.from({ length: 24 }, (_, i) => ({
  hour: i,
  latency: Math.round(40 + Math.random() * 60 + (i > 12 && i < 16 ? 30 : 0)),
}));
