// Thin client-side wrapper over the window._onemindLogEvent bridge installed by
// <Analytics/> (app/analytics.tsx). The bridge stamps first-touch attribution
// (_om_attr) onto every event and beacons it to BOTH PostHog and GA4, matching
// the live Flutter app's event names so ad-conversion + funnel reads stay
// continuous across the cutover.
//
// Safe to call anywhere: if the bridge hasn't loaded yet (or SSR), it no-ops.

type Params = Record<string, string | number | boolean | null | undefined>;

declare global {
  interface Window {
    _onemindLogEvent?: (name: string, paramsJson?: string) => void;
  }
}

export function track(name: string, params: Params = {}): void {
  if (typeof window === "undefined") return;
  try {
    window._onemindLogEvent?.(name, JSON.stringify(params));
  } catch {
    /* analytics must never break the app */
  }
}
