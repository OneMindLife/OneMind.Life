// Data access for opinion "watches" — subscribe to an opinion and get a live,
// sorted view of your watched threads that currently have matches to vote on.
// The heavy lifting is in the DB (opinion_watches + triggers keep match_count
// live); this module is the thin client over the RPCs + one realtime channel.

import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase/client";

export type WatchItem = {
  propositionId: number;
  content: string;
  newCount: number; // new opinions (replies) since you last viewed the thread
  lastActivityAt: string | null;
};

type WatchRow = {
  proposition_id: number;
  content: string | null;
  new_count: number;
  last_activity_at: string | null;
};

/// Watch / unwatch an opinion (ownership-checked server-side).
export async function setOpinionWatch(
  participantId: number,
  propositionId: number,
  watch: boolean,
): Promise<void> {
  await supabase.rpc("set_opinion_watch", {
    p_participant_id: participantId,
    p_proposition_id: propositionId,
    p_watch: watch,
  });
}

/// The live inbox: ALL your watched threads, already ordered server-side —
/// those with new replies first (most new → oldest activity), then the quiet ones.
export async function getWatched(
  participantId: number,
): Promise<WatchItem[]> {
  const { data, error } = await supabase.rpc("get_watched", {
    p_participant_id: participantId,
  });
  if (error || !data) return [];
  return (data as WatchRow[]).map((r) => ({
    propositionId: Number(r.proposition_id),
    content: String(r.content ?? ""),
    newCount: Number(r.new_count),
    lastActivityAt: r.last_activity_at ?? null,
  }));
}

/// Mark a watched thread seen (reset its unseen-replies count) — call this when
/// the user opens the thread.
export async function markWatchSeen(
  participantId: number,
  propositionId: number,
): Promise<void> {
  await supabase.rpc("mark_watch_seen", {
    p_participant_id: participantId,
    p_proposition_id: propositionId,
  });
}

/// Every opinion id this participant watches (for the watch-toggle state).
export async function getWatchedIds(
  participantId: number,
): Promise<Set<number>> {
  const out = new Set<number>();
  const { data, error } = await supabase.rpc("get_watched_ids", {
    p_participant_id: participantId,
  });
  if (error || !data) return out;
  for (const r of data as { proposition_id: number }[])
    out.add(Number(r.proposition_id));
  return out;
}

/// One filtered channel per user: fires on any change to THIS user's watch rows
/// (a match_count moving, a new/removed watch). RLS already scopes rows to the
/// user; the filter keeps the server from evaluating anyone else's.
export function subscribeWatches(
  userId: string,
  onChange: () => void,
): RealtimeChannel {
  return supabase
    .channel(`watches:${userId}`)
    .on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "opinion_watches",
        filter: `user_id=eq.${userId}`,
      },
      () => onChange(),
    )
    .subscribe();
}
