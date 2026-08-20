"use client";

import { useState } from "react";
import { shareRoom } from "@/lib/onemind/shareRoom";
import { CheckIcon, ShareIcon } from "./icons";
import css from "../TreeChat.module.css";

/// Share WHERE YOU ARE — a small icon button pinned to the right of the path.
/// At root it shares the room; inside a thread it shares THAT thread
/// (`?take=<id>`). Lives on the crumb row (a location control) rather than the
/// appbar (which is the notification family: the bell inbox + the watch eye).
export function CrumbShare({
  code,
  takeId,
  pulse = false,
  onShared,
}: {
  code: string;
  /// The opinion whose thread you're in; null at root → shares the room.
  takeId: number | null;
  /// Tutorial's final step lights this button.
  pulse?: boolean;
  onShared?: () => void;
}) {
  const [copied, setCopied] = useState(false);

  return (
    <button
      className={`${css.crumbShare} ${pulse ? css.crumbPulse : ""}`}
      onClick={async () => {
        onShared?.(); // sharing IS the last tutorial step — fire before the await
        const r = await shareRoom(code, "OneMind", takeId);
        if (r === "copied") {
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }
      }}
      type="button"
      aria-label={takeId ? "Share this thread" : "Share this chat"}
      title={
        copied
          ? "Link copied"
          : takeId
            ? "Share this thread"
            : "Share this chat"
      }
    >
      {copied ? <CheckIcon /> : <ShareIcon />}
    </button>
  );
}
