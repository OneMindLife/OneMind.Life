import type { CapacitorConfig } from "@capacitor/cli";

// Native shell that mirrors the live wedge. The point of this app is NOT to
// bundle a snapshot of the web build — it's to be a thin, near-zero-maintenance
// wrapper that loads onemind.life directly, so every `firebase deploy` updates
// the app with no store resubmission. The Flutter apps this replaces had ~0
// installs and drifted from the backend; this can't drift, because it IS the
// site.
//
// Bundle IDs differ per store (checked in the consoles 2026-07-17):
//   Android applicationId : com.onemind.onemind_app   (live Play listing)
//   iOS bundle id         : com.joelc0193.onemind     (live App Store listing)
// `appId` below is the Android/default one; the iOS target's bundle id is set
// to com.joelc0193.onemind in Xcode when the ios platform is added, so each
// binary updates the correct existing listing rather than creating a new app.
const config: CapacitorConfig = {
  appId: "com.onemind.onemind_app",
  appName: "OneMind",
  // Fallback assets only — `server.url` below is what actually loads. Capacitor
  // still requires webDir to exist with an index.html, which the static export
  // provides.
  webDir: "out",
  server: {
    // Open straight into the product, not the marketing landing. The front door
    // moved from the ranked tree (/g/GLOBAL) to the phased group chat
    // (/c/GLOBAL) on 2026-07-20; /g/GLOBAL still 302s here, but point at the
    // real URL so the app doesn't eat a redirect on every cold start.
    url: "https://onemind.life/c/GLOBAL",
    cleartext: false,
  },
};

export default config;
