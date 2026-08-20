import type { MetadataRoute } from "next";

// Required for `output: export` — the manifest must be statically generated.
export const dynamic = "force-static";

// PWA web app manifest. Without this, an installed PWA had no defined icons and
// fell back to the 32px favicon.ico — which renders blurry/"corrupt" at home-
// screen size. These are the OneMind brain icons (192/512 + maskable for
// Android adaptive icons); apple-icon.png covers iOS. Colors match --bg-0.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "OneMind",
    short_name: "OneMind",
    description:
      "Your group adds ideas, ranks them head-to-head, and converges on the answer everyone stands behind.",
    start_url: "/",
    display: "standalone",
    background_color: "#020308",
    theme_color: "#020308",
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icon-maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
      { src: "/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
