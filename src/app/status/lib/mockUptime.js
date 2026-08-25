/**
 * Mock daily uptime bars (deterministic, seeded pattern for consistency).
 */
export function generateDailyUptimeBars(count = 30) {
  const pattern = [100, 100, 99.98, 100, 100, 99.95, 100, 100, 99.99, 100,
                   100, 99.97, 100, 100, 100, 99.94, 100, 100, 99.98, 100,
                   100, 100, 99.96, 100, 100, 99.99, 100, 100, 100, 99.97];
  return pattern.slice(0, count);
}
