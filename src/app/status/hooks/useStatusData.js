/**
 * useStatusData — fetches real API data with mock fallback.
 *
 * Uses a ref-based init flag to avoid calling setState during render
 * (which React StrictMode detects as an infinite-loop risk).
 */
import { useState, useEffect, useRef, useCallback } from "react";

const POLL_INTERVAL_MS = 30_000;

export function useStatusData() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const intervalRef = useRef(null);
  const initializedRef = useRef(false);

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

  // Initial fetch + poll — all inside useEffect so no setState during render
  useEffect(() => {
    fetchData();
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
  const initializedRef = useRef(false);

  useEffect(() => {
    if (initializedRef.current) return;
    initializedRef.current = true;

    setLoading(true);
    fetch("/api/status/providers", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((json) => setProviders(json.providers || []))
      .catch((e) => setError(e))
      .finally(() => setLoading(false));
  }, []);

  return { providers, loading, error };
}
