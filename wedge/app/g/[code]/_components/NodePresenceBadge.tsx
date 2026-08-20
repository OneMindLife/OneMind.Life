"use client";

import { useNodePresence } from "../_hooks/useNodePresence";
import css from "../TreeChat.module.css";

/// "N here now" for the current node (root or a sub-thread). Self-contained so
/// its presence hook lives outside TreeChatClient's boot early-returns; it
/// re-subscribes whenever `nodeKey` changes (i.e. you navigate the tree).
///
/// Shows nothing until the channel reports at least one presence (avoids a
/// flash of "0" while the socket connects); once live it never reads below 1 —
/// you're always one of the people here.
export function NodePresenceBadge({
  chatId,
  nodeKey,
}: {
  chatId: number | null;
  nodeKey: string;
}) {
  const count = useNodePresence(chatId, nodeKey);
  if (count < 1) return null;
  const here = Math.max(1, count);
  return (
    <span
      className={css.livePresence}
      title={`${here} ${here === 1 ? "person" : "people"} viewing this right now`}
      aria-label={`${here} here now`}
    >
      <span className={css.liveDot} aria-hidden />
      {here} here
    </span>
  );
}
