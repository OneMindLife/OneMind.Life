"use client";

import { useState } from "react";
import {
  DuplicatePropositionError,
  getNodeBootstrap,
  spawnNodeCycle,
  submitProposition,
} from "@/lib/onemind/chat";
import type { TutStep } from "@/lib/onemind/tutorial";
import { AutoGrowTextarea } from "./AutoGrowTextarea";
import { TutorialFinger } from "./TutorialFinger";
import { VoteToggle } from "./VoteToggle";
import { SendButton } from "./SendButton";
import css from "../TreeChat.module.css";

// The empty leaf: the composer that lazily materializes a follow-up subround.
// Submitting spawns the child cycle, then drops the first reply into its round.
export function LeafComposer({
  propId,
  participantId,
  windowOpen,
  onChanged,
  tutStep,
  advanceTut,
}: {
  propId: number;
  participantId: number;
  windowOpen: boolean;
  onChanged: () => Promise<void> | void;
  tutStep?: TutStep;
  advanceTut?: (to: TutStep) => void;
}) {
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // The tutorial's "reply" finger — also on an EMPTY leaf (where you'd be the
  // first to reply), which ProposingSection's hint never covered.
  const showReplyHint =
    tutStep === "reply" && windowOpen && draft.trim().length === 0;

  async function send() {
    const content = draft.trim();
    if (!content || sending) return;
    setSending(true);
    setErr(null);
    try {
      await spawnNodeCycle(propId);
      const nb = await getNodeBootstrap(propId);
      const node = nb.node as Record<string, unknown> | null;
      const roundId = (node?.round as Record<string, unknown> | undefined)
        ?.id as number | undefined;
      if (!roundId) throw new Error("node round unavailable");
      await submitProposition(roundId, participantId, content);
      setDraft("");
      advanceTut?.("back"); // first reply in an empty leaf too → next: tap back up
      await onChanged();
    } catch (e) {
      setErr(
        e instanceof DuplicatePropositionError
          ? "That follow-up already exists here."
          : "Could not submit — try again.",
      );
    } finally {
      setSending(false);
    }
  }

  return (
    <section>
      <div className={css.emptyNote}>
        {windowOpen
          ? "No opinions here yet — be the first."
          : "No opinions here yet — adding opens at the next window."}
      </div>
      {showReplyHint && <TutorialFinger toX="50%" toY="calc(100dvh - 52px)" />}
      {windowOpen && (
        // Same fixed bottom dock as everywhere else, so the textfield is always
        // at the bottom of the screen (not floating inline).
        <div className={css.composerDock}>
          {showReplyHint && (
            <div className={css.tapHint} aria-hidden>
              Now add your opinion
            </div>
          )}
          <div
            className={`${css.composerCard} ${showReplyHint ? css.pulseCard : ""}`}
          >
            <AutoGrowTextarea
              value={draft}
              onChange={setDraft}
              onSubmit={() => void send()}
              placeholder="Add your opinion…"
              maxLength={600}
              disabled={sending}
            />
            <SendButton
              sending={sending}
              disabled={draft.trim().length === 0}
              onSend={() => void send()}
            />
          </div>
          {err && <div className={css.errNote}>{err}</div>}
          {/* An empty leaf has nothing to compare yet — but render the (disabled)
              Vote toggle anyway so this dock is the exact same height as every
              other level's, and the textfield never shifts as you navigate in
              and out of leaves. roundId is unused while disabled (fetch skipped). */}
          <VoteToggle
            roundId={0}
            participantId={participantId}
            active={false}
            onToggle={() => {}}
            disabled
          />
        </div>
      )}
    </section>
  );
}
