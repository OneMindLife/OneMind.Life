import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono, Instrument_Serif } from "next/font/google";
import "./globals.css";
import { Analytics } from "./analytics";
import TelegramInit from "./components/TelegramInit";
import { LangProvider } from "@/lib/i18n";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
  weight: ["200", "300", "400", "500"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
  weight: ["300", "400", "500"],
});

const instrumentSerif = Instrument_Serif({
  variable: "--font-instrument-serif",
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
});

// interactive-widget=resizes-content makes the on-screen keyboard SHRINK the
// (layout) viewport, so a `position: fixed; bottom: 0` composer sits right above
// the keyboard instead of hiding behind it. Paired with the visualViewport
// offset in TreeChatClient for iOS/webviews where this alone isn't enough.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  interactiveWidget: "resizes-content",
};

export const metadata: Metadata = {
  metadataBase: new URL("https://onemind.life"),
  // Site-wide default title — the browser tab and, for "/", the Google result.
  // Leads with the mission, matching the link-preview cards below and the
  // landing page's own mission line.
  title: "OneMind — uniting the world",
  description:
    "OneMind is the world's group chat: one room the whole world is in. Post what's on your mind, see what everyone else is saying, and vote the best lines up — every round the room's top line rises to the top. Join the world's conversation, free.",
  // Link-preview cards lead with the MISSION (2026-07-27). Set on openGraph as
  // well as twitter, not just twitter: og:title is what Telegram, LinkedIn,
  // Slack, Facebook and iMessage read, and Telegram is ~62% of our traffic — a
  // twitter-only change would leave the biggest share surface unchanged.
  // Note these override the page <title>, which still reads "the world's group
  // chat" (the browser tab and the Google result).
  openGraph: {
    title: "OneMind — uniting the world",
    description:
      "One room the whole world is in. Post what's on your mind, see what everyone's saying, and the room's best line rises to the top. Join the world's conversation.",
    url: "https://onemind.life",
    siteName: "OneMind",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "OneMind — uniting the world",
    // The old copy here was "The world's group chat — join the conversation",
    // which would have put the retired phrase straight back on the card in the
    // description line — defeating the point of retitling it.
    description:
      "One room the whole world is in. Say what you actually think, vote the best lines up, and the room's best line rises to the top.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} ${instrumentSerif.variable} antialiased`}
    >
      <body>
        <Analytics />
        <TelegramInit />
        {/* Shared cosmic backdrop — a slow breathing glow + film grain behind
            every screen (ported from the Decision Prototype). Fixed so it never
            scrolls; pointer-events:none so it never intercepts taps. */}
        <div className="ambient" aria-hidden />
        <div className="grain" aria-hidden />
        <LangProvider>{children}</LangProvider>
      </body>
    </html>
  );
}
