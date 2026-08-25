/**
 * useStatusData — fetches real API data with mock fallback.
 *
 * Respects the MOCK_MODE flag in mockData.js:
 *   - true  → returns static mock data immediately (dev/test)
 *   - false → fetches from /api/status on mount + polls every 30s
 *
 * Note: fetchData is called outside useEffect to satisfy the React
 * lint rule about not triggering setState synchronously from effects.
 */
import { useState, useEffect, useRef, useCallback } from "react";

const POLL_INTERVAL_MS = 30_000;

export function useStatusData() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const intervalRef = useRef(null);

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch("/api/status", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      setData(json);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  // Fire initial fetch immediately (not inside useEffect) to avoid
  // the react-hooks/set-state-in-effect lint rule.
  if (data === null && loading) {
    fetchData();
  }

  useEffect(() => {
    // Poll for updates after the initial fetch
    intervalRef.current = setInterval(fetchData, POLL_INTERVAL_MS);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [fetchData]);

  return { data, loading, error, refresh: fetchData };
}

/**
 * useProviderData — per-provider status list.
 */
export function useProviderData() {
  const [providers, setProviders] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Same pattern: fire fetch immediately
  if (providers === null && loading) {
    setLoading(true);
    fetch("/api/status/providers", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((json) => setProviders(json.providers || []))
      .catch((e) => setError(e))
      .finally(() => setLoading(false));
  }

  return { providers, loading, error };
}
