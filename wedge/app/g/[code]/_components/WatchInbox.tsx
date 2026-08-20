"use client";

import type { WatchItem } from "@/lib/onemind/watches";
import { BellIcon } from "./icons";
import css from "../TreeChat.module.css";

/// The appbar bell that opens the watched-threads inbox. Badge = number of
/// watched threads that currently have votes waiting.
export function WatchBell({
  badge,
  onOpen,
}: {
  badge: number;
  onOpen: () => void;
}) {
  return (
    <button
      className={css.bellBtn}
      onClick={onOpen}
      type="button"
      aria-label="Watched threads"
      title="Watched threads with new replies"
    >
      <BellIcon />
      {badge > 0 && (
        <span className={css.bellBadge}>{badge > 99 ? "99+" : badge}</span>
      )}
    </button>
  );
}

/// The notification inbox sheet: only watched threads with NEW replies since you
/// last looked, newest activity first. Tapping one jumps into it and marks it
/// seen (so it clears out). Quiet watches never appear here.
export function WatchInbox({
  items,
  onClose,
  onOpen,
}: {
  items: WatchItem[];
  onClose: () => void;
  onOpen: (propositionId: number) => void;
}) {
  return (
    <div className={css.sheetBackdrop} onClick={onClose}>
      <div
        className={css.sheet}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-label="Watching"
      >
        <div className={css.sheetHandle} aria-hidden />
        <div className={css.sheetTitle}>Watching</div>
        {items.length === 0 ? (
          <div className={css.watchEmpty}>
            All caught up. When someone replies to a thread you&apos;re watching,
            it&apos;ll show up here. You watch every opinion you post
            automatically, and any thread where you tap the 🔔.
          </div>
        ) : (
          <div className={css.watchList}>
            {items.map((it) => (
              <button
                key={it.propositionId}
                className={css.watchRow}
                onClick={() => onOpen(it.propositionId)}
                type="button"
              >
                <span className={css.watchRowText}>{it.content}</span>
                <span className={css.watchRowBadge}>
                  {it.newCount > 99 ? "99+" : it.newCount} new
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
