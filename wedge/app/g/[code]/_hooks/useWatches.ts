"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  getWatched,
  getWatchedIds,
  markWatchSeen,
  setOpinionWatch,
  type WatchItem,
} from "@/lib/onemind/watches";

/// Owns everything watch-related for the /g screen: the set of watched opinion
/// ids (for toggle state) and the notification inbox of watched threads with new
/// replies. It's a check-on-demand inbox — refetched on mount, when you open the
/// bell, and after you watch/unwatch or view a thread. No realtime (deliberately
/// removed: a reply lands as a notification, not a live-streamed update; the
/// realtime channel lives in git history / lib/onemind/watches.subscribeWatches
/// if we ever want it back). Optimistic on toggle so the bell reacts instantly.
export function useWatches(participantId: number | null) {
  const [ids, setIds] = useState<Set<number>>(() => new Set());
  const [watched, setWatched] = useState<WatchItem[]>([]);
  const participantRef = useRef(participantId);
  participantRef.current = participantId;

  const refresh = useCallback(async () => {
    const pid = participantRef.current;
    if (pid == null) return;
    const [nextIds, nextWatched] = await Promise.all([
      getWatchedIds(pid),
      getWatched(pid),
    ]);
    setIds(nextIds);
    setWatched(nextWatched);
  }, []);

  useEffect(() => {
    void refresh();
  }, [participantId, refresh]);

  const toggle = useCallback(
    async (propositionId: number) => {
      const pid = participantRef.current;
      if (pid == null) return;
      const watching = ids.has(propositionId);
      // Optimistic — the refetch in finally reconciles.
      setIds((prev) => {
        const next = new Set(prev);
        if (watching) next.delete(propositionId);
        else next.add(propositionId);
        return next;
      });
      try {
        await setOpinionWatch(pid, propositionId, !watching);
      } finally {
        void refresh();
      }
    },
    [ids, refresh],
  );

  // Mark a watched thread seen (reset its new-reply count) when the user opens
  // it, then refetch so the badge drops.
  const markSeen = useCallback((propositionId: number) => {
    const pid = participantRef.current;
    if (pid == null || !ids.has(propositionId)) return;
    void markWatchSeen(pid, propositionId).then(() => refresh());
  }, [ids, refresh]);

  // A true notification inbox: only threads with new replies since you last
  // looked. Quiet watches don't appear here — you manage those from the 🔔
  // inside the thread, not from this list. Opening one marks it seen, so it
  // drops out on the next refresh (nothing left to notify about).
  const inbox = watched.filter((w) => w.newCount > 0);

  return {
    isWatching: (propId: number) => ids.has(propId),
    inbox, // watched threads with unseen replies, new-first (server-sorted)
    badge: inbox.length, // badge and list always agree
    toggle,
    markSeen,
    refresh,
  };
}
