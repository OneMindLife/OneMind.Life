"use client";

import { useEffect, useState } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase, ensureSignedIn } from "@/lib/supabase/client";

/// Live "who's here right now" for the CURRENT NODE — root or any sub-thread.
///
/// Same lightweight mechanism as lib/onemind/usePresence (Supabase Realtime
/// Presence: a websocket channel that tracks OPEN CONNECTIONS, NOT a postgres
/// data subscription — so it does NOT reintroduce the realtime cascade the app
/// is careful to avoid). The difference: the channel is keyed by
/// (chatId, nodeKey), so the count reflects only co-viewers of the exact node
/// you're looking at.
///
/// Navigating the tree changes `nodeKey` → this effect tears down the old
/// node's channel and joins the new one, and each node's count updates live for
/// everyone standing on it. Count = distinct presence keys (= distinct users;
/// a person's multiple tabs collapse to one via the uid key). Backgrounded
/// mobile tabs suspend the socket, so this honestly means "actively here".
///
/// Called from a small child component (NodePresenceBadge) rather than inline in
/// TreeChatClient, so its hooks stay clear of that component's boot early-returns.
export function useNodePresence(
  chatId: number | null,
  nodeKey: string | null,
): number {
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (chatId == null || nodeKey == null) return;
    let channel: RealtimeChannel | null = null;
    let alive = true;
    setCount(0); // reset while (re)joining the new node's channel

    (async () => {
      const session = await ensureSignedIn();
      const uid = session?.user?.id;
      if (!alive || !uid) return;

      channel = supabase.channel(`presence:node:${chatId}:${nodeKey}`, {
        config: { presence: { key: uid } },
      });

      channel
        .on("presence", { event: "sync" }, () => {
          if (!channel) return;
          setCount(Object.keys(channel.presenceState()).length);
        })
        .subscribe((status) => {
          if (status === "SUBSCRIBED") {
            void channel?.track({ at: new Date().toISOString() });
          }
        });
    })();

    return () => {
      alive = false;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [chatId, nodeKey]);

  return count;
}
