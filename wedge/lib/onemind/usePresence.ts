"use client";

import { useEffect, useState } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase, ensureSignedIn } from "@/lib/supabase/client";

/// Live "who's here right now" count via Supabase Realtime Presence — a
/// lightweight websocket channel that tracks open connections (NOT a postgres
/// data subscription, so it doesn't reintroduce the realtime cascade we avoid).
///
/// The server is the source of truth: each open client `track()`s itself; the
/// count is the number of distinct presence keys (= distinct users; multiple
/// tabs of one person collapse to one). Disconnects (tab close, navigate away)
/// drop near-instantly; ungraceful drops (network/phone sleep) time out after a
/// protocol-heartbeat window. On mobile a backgrounded tab suspends the socket,
/// so this honestly means "actively here", not "has it open somewhere".
///
/// Mount ONCE per chat view (at ChatClient) so the single channel persists
/// across phase changes instead of leave/rejoin-churning each transition.
export function usePresence(chatId: number | null): number {
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (chatId == null) return;
    let channel: RealtimeChannel | null = null;
    let alive = true;

    (async () => {
      const session = await ensureSignedIn();
      const uid = session?.user?.id;
      if (!alive || !uid) return;

      channel = supabase.channel(`presence:chat:${chatId}`, {
        config: { presence: { key: uid } },
      });

      channel
        .on("presence", { event: "sync" }, () => {
          if (!channel) return;
          setCount(Object.keys(channel.presenceState()).length);
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") {
            void channel?.track({ online_at: new Date().toISOString() });
          }
        });
    })();

    return () => {
      alive = false;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [chatId]);

  return count;
}
