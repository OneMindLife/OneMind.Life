"use client";

import { useState } from "react";
import {
  DuplicatePropositionError,
  getNodeBootstrap,
  spawnNodeCycle,
  submitProposition,
} from "@/lib/onemind/chat";
import type { ComposeTarget } from "@/lib/onemind/fabState";
import { AutoGrowTextarea } from "./AutoGrowTextarea";
import { SendButton } from "./SendButton";
import css from "../TreeChat.module.css";

/// The opinion composer, pinned to the TOP of every list — root, thread, and
/// empty leaf, identical at every depth. Being the first thing you see makes
/// "you can add yours to this list" self-evident and lets people picture their
/// take joining the ranking below; the old Post FAB hid that behind a tap and
/// a sheet, and posting fell to ~zero. Deliberately NOT autofocused: it's always
/// on screen, so grabbing the keyboard on arrival would fight the browse-first
/// read.
///
/// Placeholder: "Speak freely — anonymously". It keeps the bar on the FLOOR —
/// "speak freely" grants permission (say the honest thing, no fear), it doesn't
/// demand quality — and it names the product's actual promise (freedom from
/// judgment) while reassuring anonymity at the exact moment of vulnerability
/// (the fair-apparatus principle). A quality-flavored prompt would set a
/// standard to live up to ("say what you really think" quietly demands a
/// considered, defensible opinion; a question demands an answer that fits it),
/// and supply is the constraint. The ranked list right
/// below IS the real prompt: people read the genre off the existing takes far
/// better than a hint could teach it. We don't filter at the door — the votes
/// filter, and junk sinks. See memory: collective_axis_no_comparability_needed.
export function OpinionComposer({
  target,
  participantId,
  onPosted,
}: {
  /// Where a post lands: the live round, or an empty leaf whose thread it spawns.
  target: ComposeTarget;
  participantId: number;
  onPosted: (newPropId: number | null) => Promise<void> | void;
}) {
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const query = draft.trim();

  async function send() {
    const content = draft.trim();
    if (!content || sending) return;
    setSending(true);
    setErr(null);
    try {
      let roundId: number;
      if (target.kind === "round") {
        roundId = target.roundId;
      } else {
        // Empty leaf: materialize its child cycle, then post into its round.
        await spawnNodeCycle(target.propId);
        const nb = await getNodeBootstrap(target.propId);
        const node = nb.node as Record<string, unknown> | null;
        const rid = (node?.round as Record<string, unknown> | undefined)?.id as
          | number
          | undefined;
        if (!rid) throw new Error("node round unavailable");
        roundId = rid;
      }
      const newId = await submitProposition(roundId, participantId, content);
      setDraft(""); // stays open — adding another should cost nothing
      await onPosted(newId);
    } catch (e) {
      setErr(
        e instanceof DuplicatePropositionError
          ? "That opinion already exists here."
          : "Could not post — try again.",
      );
    } finally {
      setSending(false);
    }
  }

  return (
    <div className={css.topComposer}>
      <div className={css.composerCard}>
        {/* Lock glyph — the safety cue right at the input, where you hesitate:
            what you say here is anonymous. Reinforces the trust strip. */}
        <span className={css.composerLock} aria-hidden>
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M18 8h-1V6A5 5 0 0 0 7 6v2H6a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V10a2 2 0 0 0-2-2zM9 6a3 3 0 0 1 6 0v2H9V6z" />
          </svg>
        </span>
        <AutoGrowTextarea
          value={draft}
          onChange={setDraft}
          onSubmit={() => void send()}
          placeholder="Speak freely — anonymously"
          maxLength={600}
          disabled={sending}
        />
        <SendButton
          sending={sending}
          disabled={query.length === 0}
          onSend={() => void send()}
          label="Post your opinion"
        />
      </div>
      {err && <div className={css.errNote}>{err}</div>}
      {/* No match-as-you-type here on purpose: the box does ONE thing — say
          something. Conflating it with a finder made every keystroke surface
          noisy near-matches (they scored on filler words), which just teaches
          people to ignore the box. Finding is a deliberate act with its own
          control — the 🔍 on the ranking header. */}
    </div>
  );
}
