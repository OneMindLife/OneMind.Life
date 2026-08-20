"use client";

// /g/<code> — the wedge rendering of the Flutter branching-chat UI as a
// NAVIGABLE WEB (docs/ONEMIND_CONCEPT.md C15): the user arrives at position
// 1 and sees ALL of round 1's options (final-ranking order). Picking one
// commits it (teal card) and reveals the next level — deeper options, a live
// round's proposing feed / duel, or an empty leaf with a composer that
// lazily materializes the follow-up subround. Tapping a committed card
// reopens that level. Zero-friction: arriving at the URL auto-joins.

import { Fragment, useCallback, useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { supabase } from "@/lib/supabase/client";
import {
  ensureParticipant,
  getChatByCode,
  getNodeBootstrap,
  getPropositionPath,
  getRankedProps,
  getRootRounds,
  loadBootstrap,
  type Bootstrap,
  type WalkProp,
  type WalkRound,
} from "@/lib/onemind/chat";
import { deriveClock } from "@/lib/onemind/globalChat";
import { walkTree, type NodeSnapshot } from "@/lib/onemind/treeWalk";
import { useKeyboardInset } from "./_hooks/useKeyboardInset";
import { useLevelNavigation } from "./_hooks/useLevelNavigation";
import { useTutorial } from "./_hooks/useTutorial";
import { useWatches } from "./_hooks/useWatches";
import { WatchBell, WatchInbox } from "./_components/WatchInbox";
import { EyeIcon, EyeOffIcon } from "./_components/icons";
import { DuelSection } from "./_components/DuelSection";
import { LeafComposer } from "./_components/LeafComposer";
import { ProposingSection } from "./_components/ProposingSection";
import {
  composeTargetFor,
  type ComposeTarget,
} from "@/lib/onemind/fabState";
import { AppbarMenu } from "./_components/AppbarMenu";
import { NodePresenceBadge } from "./_components/NodePresenceBadge";
import { PostedShareCard } from "./_components/PostedShareCard";
import { ConceptSheet } from "./_components/ConceptSheet";
import { ConceptReveal } from "./_components/ConceptReveal";
import {
  hasSeenReveal,
  markRevealSeen,
  REVEAL_COPY,
  type RevealKey,
} from "@/lib/onemind/conceptReveals";
import { CrumbShare } from "./_components/CrumbShare";
import { ActionFabs } from "./_components/ActionFabs";
import { OpinionComposer } from "./_components/OpinionComposer";
import { PushOptInCard } from "./_components/PushOptInCard";
import { usePushOptIn } from "./_hooks/usePushOptIn";
import { canonicalForCode } from "@/lib/onemind/canonical";
import css from "./TreeChat.module.css";

/// Upsert the page's <link rel="canonical">. The /g shell is shared across all
/// codes, so the correct canonical is only knowable client-side (see
/// lib/onemind/canonical.ts). Google renders JS and honors the rendered tag.
function setCanonical(href: string): void {
  if (typeof document === "undefined") return;
  let link = document.head.querySelector<HTMLLinkElement>(
    'link[rel="canonical"]',
  );
  if (!link) {
    link = document.createElement("link");
    link.rel = "canonical";
    document.head.appendChild(link);
  }
  link.href = href;
}

type Boot =
  | { kind: "loading" }
  | { kind: "error"; message: string }
  | { kind: "ready"; data: Bootstrap; participantId: number };

function codeFromPath(path: string | null): string | null {
  const m = (path ?? "").match(/\/g\/([^/]+)/);
  return m ? decodeURIComponent(m[1]).toUpperCase() : null;
}

// Path-crumb label: keep it short so the breadcrumb stays on one line. First 3
// words, hard-capped at 24 chars on a word boundary; "…" if anything was cut.
function crumbLabel(text: string): string {
  const full = text.trim().replace(/\s+/g, " ");
  const words = full.split(" ");
  let label = words.slice(0, 3).join(" ");
  if (label.length > 24) label = label.slice(0, 24).replace(/\s+\S*$/, "");
  return label.length < full.length ? label + "…" : label;
}


export default function TreeChatClient({
  seoCodes = [],
}: {
  seoCodes?: string[];
}) {
  const pathname = usePathname();
  const code = codeFromPath(pathname);

  // Point this /g/<code> view's canonical at its /opinions content page when one
  // exists, else a param-stripped self-canonical — clears Search Console's
  // "Duplicate without user-selected canonical" and collapses ?take= variants.
  useEffect(() => {
    if (!code) return;
    setCanonical(canonicalForCode(code, seoCodes));
  }, [code, seoCodes]);
  // Deep-link: /g/<code>?take=<propId> auto-descends the walk onto that
  // proposition (the Telegram daily-frontier button lands here). Read once.
  const takeId =
    typeof window !== "undefined"
      ? Number(new URLSearchParams(window.location.search).get("take"))
      : NaN;
  const appliedTake = useRef(false);
  const [boot, setBoot] = useState<Boot>({ kind: "loading" });
  const [now, setNow] = useState(() => new Date());
  const chatIdRef = useRef<number | null>(null);
  // The opinion the user JUST posted — we descend into it and show the "your
  // take is live · share it" card on its (empty) thread. Cleared when they
  // navigate away (the card is gated on justPosted === leafProp).
  const [justPosted, setJustPosted] = useState<number | null>(null);

  // ── Level navigation ────────────────────────────────────────────────────
  // The committed-choices map (push/pop down the tree), per-level scroll memory,
  // and the list slide all live in this hook; the pure choice math is unit-tested
  // in lib/onemind/levelNav. `rememberLevel` is called each render with the
  // current on-screen level key (derived below from the walk).
  const {
    choices,
    slideRef,
    crumbRef,
    rememberLevel,
    descend,
    jumpTo: jumpToChoice,
    applyPath,
  } = useLevelNavigation();
  // Browse-first: you always land on the LIST (read what people think). Voting
  // is an OPPORTUNITY you choose — tap the glowing Vote FAB to weigh in — never
  // forced. No auto-drop, no lock; the duel is a mode you enter and leave freely.
  const [tab, setTab] = useState<"replies" | "vote">("replies");
  // Watch feature: the notification inbox (checked on demand — no realtime).
  const [inboxOpen, setInboxOpen] = useState(false);
  // "What is OneMind?" concept explainer, opened on demand from the ⋮ menu.
  const [conceptOpen, setConceptOpen] = useState(false);
  // Theme: Daylight is the identity (default), "Voting Booth" is an opt-in night
  // mode. Just flips data-theme on the .page — all colors are design tokens, so
  // the dark block redefines them. Persisted; SSR renders light to avoid a flash.
  const [theme, setTheme] = useState<"light" | "dark">("light");
  useEffect(() => {
    try {
      if (localStorage.getItem("om_theme") === "dark") setTheme("dark");
    } catch {
      /* private mode */
    }
  }, []);
  const toggleTheme = useCallback(() => {
    setTheme((t) => {
      const next = t === "dark" ? "light" : "dark";
      try {
        localStorage.setItem("om_theme", next);
      } catch {
        /* private mode */
      }
      return next;
    });
  }, []);
  // Just-in-time concept reveals: teach the model at the moment it becomes real
  // (first duel, first branch). Declared HERE, above the boot early-returns —
  // hooks must run unconditionally every render (React #310). The reveals are
  // fired imperatively from the vote/openThread handlers, not from an effect
  // that depends on the post-return `liveStop`/`hasPair`. Shown once per concept.
  const [activeReveal, setActiveReveal] = useState<RevealKey | null>(null);
  const fireReveal = useCallback((key: RevealKey) => {
    if (hasSeenReveal(key)) return;
    setActiveReveal((cur) => cur ?? key); // don't stack — first one wins
  }, []);
  const dismissReveal = useCallback(() => {
    setActiveReveal((key) => {
      if (key) markRevealSeen(key);
      return null;
    });
  }, []);
  const watchParticipantId = boot.kind === "ready" ? boot.participantId : null;
  const watches = useWatches(watchParticipantId);

  // Push re-engagement: offered once, at peak intent — right after the user
  // posts an opinion (auto-watched) so the "someone replied" ping can pull them
  // back. This is the return leg of the retention loop; notify_push_watch_reply
  // is the server half.
  const pushOptIn = usePushOptIn();

  // Lightweight guided nudges (vote → reply → share) that light the relevant
  // surface for a first-timer and advance forward-only. The old "replay the
  // whole mechanics tour" entry point is gone — concept is taught by the
  // ConceptSheet (on demand) and just-in-time reveals, not a re-runnable tour.
  const { step: tutStep, advance: advanceTut } = useTutorial();

  // A brief celebratory payoff the moment the tutorial completes — fired
  // deterministically from the Share action (the last step), not inferred from
  // step transitions (which race with the hydrate).
  const [justFinishedTut, setJustFinishedTut] = useState(false);
  const celebrateTutorial = useCallback(() => {
    setJustFinishedTut(true);
    setTimeout(() => setJustFinishedTut(false), 4500);
  }, []);

  // Keep the fixed composer above the on-screen keyboard (never scrolling behind
  // it) — sets the --kb-bottom CSS var from visualViewport.
  useKeyboardInset();

  const [rootRounds, setRootRounds] = useState<WalkRound[] | null>(null);
  const [propsByRound, setPropsByRound] = useState<Record<number, WalkProp[]>>(
    {},
  );
  const [nodes, setNodes] = useState<Record<number, NodeSnapshot>>({});
  const fetchingRounds = useRef<Set<number>>(new Set());
  const fetchingNodes = useRef<Set<number>>(new Set());

  const fetchRoundProps = useCallback((roundId: number) => {
    if (fetchingRounds.current.has(roundId)) return;
    fetchingRounds.current.add(roundId);
    getRankedProps(roundId)
      .then((p) => setPropsByRound((prev) => ({ ...prev, [roundId]: p })))
      .catch(() => {})
      .finally(() => fetchingRounds.current.delete(roundId));
  }, []);

  const fetchNode = useCallback((propId: number) => {
    if (fetchingNodes.current.has(propId)) return;
    fetchingNodes.current.add(propId);
    getNodeBootstrap(propId)
      .then((nb) => setNodes((prev) => ({ ...prev, [propId]: nb })))
      .catch(() => {})
      .finally(() => fetchingNodes.current.delete(propId));
  }, []);

  const refresh = useCallback(async () => {
    const chatId = chatIdRef.current;
    if (chatId == null) return;
    try {
      const [data, roots] = await Promise.all([
        loadBootstrap(chatId),
        getRootRounds(chatId),
      ]);
      if (data) {
        setBoot((prev) =>
          prev.kind === "ready" ? { ...prev, data } : prev,
        );
      }
      setRootRounds(roots);
      // Refresh every cached level so the walk is live end-to-end.
      setPropsByRound((prev) => {
        Object.keys(prev).forEach((rid) => {
          fetchingRounds.current.delete(Number(rid));
          fetchRoundProps(Number(rid));
        });
        return prev;
      });
      setNodes((prev) => {
        Object.keys(prev).forEach((pid) => {
          fetchingNodes.current.delete(Number(pid));
          fetchNode(Number(pid));
        });
        return prev;
      });
    } catch {
      /* transient — next refresh wins */
    }
  }, [fetchNode, fetchRoundProps]);


  // ── Boot ────────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!code) {
      setBoot({ kind: "error", message: "No chat code in the URL." });
      return;
    }
    let alive = true;
    (async () => {
      try {
        const chat = await getChatByCode(code);
        if (!chat) throw new Error("This chat doesn't exist.");
        const joined = await ensureParticipant(chat);
        if (joined.status !== "in") {
          throw new Error("This chat requires host approval to join.");
        }
        chatIdRef.current = chat.id;
        const [data, roots] = await Promise.all([
          loadBootstrap(chat.id),
          getRootRounds(chat.id),
        ]);
        if (!alive || !data) return;
        setRootRounds(roots);
        setBoot({ kind: "ready", data, participantId: joined.participantId });
      } catch (e) {
        if (alive) {
          setBoot({
            kind: "error",
            message:
              e instanceof Error ? e.message : "Could not open the chat.",
          });
        }
      }
    })();
    return () => {
      alive = false;
    };
  }, [code]);

  // 1s countdown tick.
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  // Live updates: propositions INSERT (chat-wide) + a 30s poll safety net.
  useEffect(() => {
    if (boot.kind !== "ready") return;
    const chatId = chatIdRef.current;
    if (chatId == null) return;
    const channel = supabase
      .channel(`tree_g_${chatId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "propositions",
          filter: `chat_id=eq.${chatId}`,
        },
        () => void refresh(),
      )
      .subscribe();
    const poll = setInterval(() => void refresh(), 30000);
    return () => {
      clearInterval(poll);
      void supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [boot.kind]);

  // Phase flips arrive as rounds UPDATEs — subscribe per the frontier cycle.
  const currentCycleId =
    boot.kind === "ready"
      ? ((boot.data.current_round as Record<string, unknown> | null)
          ?.cycle_id as number | undefined)
      : undefined;
  useEffect(() => {
    if (currentCycleId == null) return;
    const channel = supabase
      .channel(`tree_g_rounds_${currentCycleId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "rounds",
          filter: `cycle_id=eq.${currentCycleId}`,
        },
        () => void refresh(),
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [currentCycleId, refresh]);

  // Deep-link auto-descend: once the chat is loaded, fetch the target's
  // root→target path and pre-commit the walk's choices so it descends onto it.
  // Runs once. The walk's lazy node-fetching carries it down level by level.
  useEffect(() => {
    if (appliedTake.current) return;
    if (boot.kind !== "ready" || !rootRounds || rootRounds.length === 0) return;
    if (!Number.isFinite(takeId) || takeId <= 0) return;
    appliedTake.current = true;
    getPropositionPath(takeId)
      .then((path) => {
        if (path.length) applyPath(path);
      })
      .catch(() => {});
  }, [boot.kind, rootRounds, takeId, applyPath]);

  // ── Early states ────────────────────────────────────────────────────────
  if (boot.kind === "loading") {
    return (
      <div className={css.page}>
        <div className={css.boot}>
          <div className={css.spinner} />
        </div>
      </div>
    );
  }
  if (boot.kind === "error") {
    return (
      <div className={css.page}>
        <div className={css.boot}>
          <div className={css.bootErr}>{boot.message}</div>
        </div>
      </div>
    );
  }

  const { data, participantId } = boot;
  // Repository mode (never_seals): always alive — browse + add, and place
  // (rank) whenever you want, no proposing/voting phase gate.
  const repository =
    (data.chat as Record<string, unknown> | undefined)?.never_seals === true;

  // ── The walk ────────────────────────────────────────────────────────────
  // Pure navigation core (lib/onemind/treeWalk.ts): given the loaded data +
  // the user's committed choices, it yields the spine to render, the live stop,
  // the composer leaf, and which round/node data still needs fetching. This
  // component is a thin renderer over that result.
  const walk = walkTree({
    roots: rootRounds ?? [],
    data,
    propsByRound,
    nodes,
    choices,
    repository,
  });
  const { chain, liveStop, leafProp, leafWindowOpen, pending } = walk;

  // ── Action-FAB inputs (pure derivations; the Vote FAB fetches its own count) ─
  const voteActive = tab === "vote";
  // A pair is needed to compare — the Vote FAB is inert below 2 opinions.
  const hasPair =
    liveStop != null && liveStop.props.filter((p) => p.id > 0).length >= 2;

  // The Post FAB always lands somewhere: the live round, or (on an empty leaf)
  // the leaf whose thread it spawns.
  const postTarget: ComposeTarget | null = composeTargetFor(
    liveStop?.round.id ?? null,
    leafProp,
  );

  // Fire the fetches the walk asked for (each fetcher is ref-guarded against
  // duplicates, so calling every render is cheap and idempotent — same timing
  // as the previous inline walk).
  walk.needRounds.forEach(fetchRoundProps);
  walk.needNodes.forEach(fetchNode);

  // Single-level navigation: only the current level's opinions fill the screen.
  // Instead of a Back button, a tappable PATH breadcrumb (root → … → here) walks
  // up: each committed step aligns 1:1 with a `chain` entry (both pushed together
  // in the walk), so crumb i ↔ committedSteps[i].key.
  const committedSteps = walk.steps.filter((s) => s.kind === "committed");

  // Identity of the level currently on screen (per-level scroll memory keys off
  // it). Reported to the nav hook every render so its effects act on the NEW
  // level after a navigation commits.
  const levelKey = String(liveStop?.key ?? "root");
  rememberLevel(levelKey);

  // Presence key for "who's here now" on the CURRENT node: the live stop's node
  // id, else the empty-leaf's id, else the root sentinel. Distinct per node so
  // co-viewers of the same node share one presence channel (useNodePresence).
  const presenceKey = String(liveStop?.key ?? leafProp ?? "root");

  // `descend` comes straight from the hook. `jumpTo` wraps the hook's jump with
  // the one tutorial side-effect (advancing the "back" step), keeping the hook
  // free of tutorial concerns. Crumb i ↔ committedSteps[i].key.
  // Navigating ALWAYS lands you on that level's list, never mid-duel. The duel
  // is a per-node mode you opt into; carrying `tab === "vote"` across a jump
  // dumped you into a duel for a node you never chose to vote on (and if it had
  // no pair for you, straight into the "all done" box you never earned).
  const committedKeys = committedSteps.map((s) => s.key);
  const jumpTo = (i: number) => {
    setTab("replies");
    jumpToChoice(committedKeys, i);
    if (tutStep === "back") advanceTut("vote");
  };
  // Descend into an opinion's thread AND mark it seen if watched (viewing it
  // clears its new-reply count). markSeen is a no-op when you don't watch it.
  const openThread = (key: number, propId: number) => {
    setTab("replies");
    descend(key, propId);
    watches.markSeen(propId);
    fireReveal("branch"); // first descent teaches "any opinion can branch"
  };

  // THE SPINE. Every committed node stays on screen, stacked, as you go deeper —
  // so the whole chain of context is readable at a glance and you can tap any
  // card to jump back to that level (the breadcrumb does the same job in one
  // line; both work). Without this, a thread showed replies to an INVISIBLE
  // question — anyone arriving by ?take= link had to back out to find out what
  // they'd landed in. The walk has always emitted these steps; they just weren't
  // rendered (removed in 71825cc8's single-level experiment).
  let committedSeen = -1;
  const blocks = walk.steps.map((step) => {
    if (step.kind === "committed") {
      committedSeen += 1;
      const level = committedSeen; // crumb i ↔ committedSteps[i]
      const isCurrent = level === committedSteps.length - 1;
      return (
        <button
          key={`c_${step.key}`}
          className={`${css.spineCard} ${isCurrent ? css.spineCurrent : ""}`}
          // Tapping a committed card REOPENS THE LEVEL WHERE IT WAS CHOSEN, so
          // you can pick a different sibling. jumpTo(i) keeps i+1 choices —
          // i.e. "be inside chain[i]" — so the level that lists this card is
          // i-1 (and level 0 → -1 → root). Passing `level` here made the
          // deepest card a no-op: it jumped to where you already were.
          onClick={() => jumpTo(level - 1)}
          type="button"
          title="Back to where this was chosen"
        >
          <span className={css.text}>{step.content}</span>
        </button>
      );
    }
    return step.kind === "options" ? (
      <div key={`opts_${step.key}`}>
        <div className={`${css.levelHeader} ${css.actionHeader}`}>
          <span className={css.levelHeaderText}>OPEN A THREAD</span>
        </div>
        {step.options.map((p) => (
          <button
            key={p.id}
            className={`${css.feedCard} ${css.optionCard}`}
            onClick={() => openThread(step.key, p.id)}
            type="button"
          >
            <span className={css.text}>{p.content}</span>
            {p.participant_id == null && <span className={css.aiTag}>AI</span>}
          </button>
        ))}
      </div>
    ) : null;
  });


  const clock = deriveClock(liveStop?.round ?? null, now);

  return (
    <div className={css.page} data-theme={theme}>
      <div className={css.appbar}>
        <div className={css.appbarRow}>
          {/* Watched-threads bell (left). Non-repo chats keep a spacer so the
              title stays centered. */}
          {repository ? (
            <div className={css.appbarLeft}>
              <WatchBell
                badge={watches.badge}
                onOpen={() => {
                  watches.refresh(); // fresh notifications each time you check
                  setInboxOpen(true);
                }}
              />
              {/* Watch THIS thread — an EYE right of the bell so the two
                  notification controls read as a pair (the bell is "what I'm
                  notified about", the eye is "add this to that"). Shown only
                  inside an opinion; watching the chat's root is a separate
                  default-on subscription (added with the root-watch backend). */}
              {chain.length > 0 ? (
                <button
                  className={`${css.appbarEye} ${
                    watches.isWatching(chain[chain.length - 1].propId)
                      ? css.appbarEyeOn
                      : ""
                  }`}
                  onClick={() => watches.toggle(chain[chain.length - 1].propId)}
                  type="button"
                  aria-pressed={watches.isWatching(
                    chain[chain.length - 1].propId,
                  )}
                  aria-label={
                    watches.isWatching(chain[chain.length - 1].propId)
                      ? "Stop watching this thread"
                      : "Watch this thread"
                  }
                  title={
                    watches.isWatching(chain[chain.length - 1].propId)
                      ? "Watching — new replies show up in your 🔔 inbox"
                      : "Watch this thread for new replies"
                  }
                >
                  {watches.isWatching(chain[chain.length - 1].propId) ? (
                    <EyeIcon />
                  ) : (
                    <EyeOffIcon />
                  )}
                </button>
              ) : (
                /* Reserve the eye's footprint at root so the centered title
                   doesn't jump when the eye appears crossing into a thread.
                   (Piece 2's root-watch will put a real eye here.) */
                <span className={css.appbarEye} aria-hidden />
              )}
            </div>
          ) : (
            <span className={css.appbarSpacer} aria-hidden />
          )}
          <div className={css.appbarTitle}>OneMind</div>
          {/* Live "who's here now" for the CURRENT node (root or thread) —
              re-subscribes as you navigate. Child component so its presence hook
              stays clear of this component's boot early-returns. */}
          <NodePresenceBadge chatId={chatIdRef.current} nodeKey={presenceKey} />
          {/* One ⋮ menu — How it works · Source code · Share. */}
          <AppbarMenu
            onExplainConcept={() => setConceptOpen(true)}
            theme={theme}
            onToggleTheme={toggleTheme}
          />
        </div>
      </div>

      {/* Trust strip — the fair machine announces its fairness, right up top, so
          a stranger feels safe before they read a word. Depersonalization: this
          reads as an impartial record, not a social room. */}
      {repository && (
        <div className={css.trustStrip}>
          <svg viewBox="0 0 24 24" aria-hidden>
            <path d="M12 1 3 5v6c0 5.5 3.8 10.7 9 12 5.2-1.3 9-6.5 9-12V5l-9-4z" />
          </svg>
          Anonymous · ranked only by votes · no names
        </div>
      )}

      <div className={css.col}>
        {tutStep === "share" && (
          <div className={css.tapHint} aria-hidden>
            Last step — tap Share to invite others
          </div>
        )}
        {/* Tappable PATH breadcrumb (root → … → here). Each segment walks back up
            to that level. Always rendered — at root it's just a disabled ⌂ so the
            bar reserves its height and nothing jitters when you first descend. */}
        {(liveStop || chain.length > 0) && (
          <div className={css.crumbRow}>
            {/* ⌂ lives OUTSIDE the scrolling nav so it never scrolls out of
                view: the nav auto-scrolls to its right edge to keep the deepest
                crumb visible, which would otherwise carry the home button off
                the left. Pinned here, only the crumbs scroll under it. */}
            <button
              className={`${css.crumb} ${css.crumbHome} ${
                tutStep === "back" ? css.crumbPulse : ""
              }`}
              onClick={() => jumpTo(-1)}
              type="button"
              disabled={chain.length === 0}
              aria-label="Back to all opinions"
              title={chain.length === 0 ? "All opinions" : "Back to all opinions"}
            >
              ⌂
            </button>
            <nav className={css.crumbBar} aria-label="Path" ref={crumbRef}>
              {chain.map((link, i) => {
                const isLast = i === chain.length - 1;
                return (
                  <Fragment key={`${link.propId}_${i}`}>
                    <span className={css.crumbSep} aria-hidden>
                      /
                    </span>
                    <button
                      className={`${css.crumb} ${
                        isLast ? css.crumbCurrent : ""
                      }`}
                      onClick={() => jumpTo(i)}
                      type="button"
                      aria-current={isLast ? "page" : undefined}
                      title={link.text}
                    >
                      {crumbLabel(link.text)}
                    </button>
                  </Fragment>
                );
              })}
            </nav>
            {/* Share WHERE YOU ARE — pinned right of the (scrolling) path,
                because that's the control that means "this location". The watch
                EYE moved OFF the crumb row and up to the appbar next to the bell
                (the notification family lives together there); the crumb row is
                purely location now: ⌂ + path + share. */}
            {repository && (
              <CrumbShare
                code={code ?? ""}
                takeId={chain.length > 0 ? chain[chain.length - 1].propId : null}
                pulse={tutStep === "share"}
                onShared={() => {
                  if (tutStep === "share") {
                    advanceTut("done");
                    celebrateTutorial();
                  }
                }}
              />
            )}
          </div>
        )}
        {tutStep === "back" && chain.length > 0 && (
          <div className={css.tapHint} aria-hidden>
            Tap ⌂ to return
          </div>
        )}
        {/* Only the LIST slides on navigation (animated imperatively in an effect
            via `left`, so the region is never remounted and the fixed composer
            dock inside it doesn't jitter). The crumb bar above and the
            composer/vote dock below never move; only this content swaps. */}
        <div className={css.slideRegion} ref={slideRef}>
          {/* JIT concept reveal — heads the view you just landed on (the duel,
              or the thread you branched into), in-flow so it never covers the
              bottom dock/FAB. Shown once per concept, ever. */}
          {activeReveal && (
            <ConceptReveal
              text={REVEAL_COPY[activeReveal]}
              onDismiss={dismissReveal}
            />
          )}
          {chain.length === 0 && data.chat.initial_message ? (
            <div className={css.spine}>
              <div className={css.questionCard}>
                {String(data.chat.initial_message)}
              </div>
            </div>
          ) : null}

          {blocks}

        {pending && (
          <div className={css.boot} style={{ minHeight: "20dvh" }}>
            <div className={css.spinner} />
          </div>
        )}

        {/* (The parent you're replying to is the last card of the SPINE above —
            no separate "replying to" card, or the same node renders twice.) */}

        {/* The opinion composer leads EVERY list (root, thread, empty leaf) —
            same UI at every depth, so "add yours to this list" is the first
            thing you see and the ranking below is visibly what you'd join.
            Hidden only while the duel is up (the list isn't there to join). */}
        {repository && !voteActive && postTarget && (
          <OpinionComposer
            target={postTarget}
            participantId={participantId}
            onPosted={async (newId) => {
              await refresh();
              // Drop them INTO their new opinion (their "supply") — descend from
              // the level they posted at into the just-created opinion, and flag
              // it so its thread shows the "your take is live · share it" card.
              // This is the peak-intent moment for the share loop (the top growth
              // lever). The notify opt-in now lives inside that card.
              const key = liveStop?.key ?? leafProp;
              if (newId != null && key != null) {
                setTab("replies");
                descend(key, newId);
                setJustPosted(newId);
              } else {
                pushOptIn.maybeOffer(); // fallback if we didn't get the id
              }
            }}
          />
        )}

        {/* Repository (GLOBAL) mode: browse the list by default; the head-to-head
            duel only when YOU tap the Vote FAB. */}
        {liveStop &&
          repository &&
          (voteActive && hasPair ? (
            <DuelSection
              key={liveStop.round.id}
              roundId={liveStop.round.id}
              board={liveStop.props}
              participantId={participantId}
              remainingSec={clock.remaining}
              onChanged={refresh}
              onExit={() => setTab("replies")}
              onVoted={() => pushOptIn.maybeOffer()}
              advanceTut={advanceTut}
              tutVote={tutStep === "vote"}
            />
          ) : (
            <ProposingSection
              roundId={liveStop.round.id}
              board={liveStop.props}
              participantId={participantId}
              remainingSec={clock.remaining}
              onChanged={refresh}
              onOpen={(propId) => openThread(liveStop!.key, propId)}
              repository
              listOnly
              isReply={chain.length > 0}
              tutStep={tutStep}
              advanceTut={advanceTut}
            />
          ))}
        {/* Repository leaf (a childless opinion): the composer above is the whole
            screen — posting here spawns the thread. Just after posting, THIS is
            the opinion they made → the "your take is live · share it" moment. */}
        {!pending && !liveStop && leafProp != null && repository && (
          justPosted === leafProp && code ? (
            <PostedShareCard
              code={code}
              propId={leafProp}
              pushOptIn={pushOptIn}
            />
          ) : (
            <div className={css.emptyNote}>
              No opinions here yet — be the first to weigh in.
            </div>
          )
        )}

        {/* Non-repository chats: the classic phase-gated flow with inline composer. */}
        {liveStop && !repository && liveStop.round.phase === "proposing" && (
          <ProposingSection
            roundId={liveStop.round.id}
            board={liveStop.props}
            participantId={participantId}
            remainingSec={clock.remaining}
            onChanged={refresh}
            onOpen={(propId) => openThread(liveStop!.key, propId)}
            isReply={chain.length > 0}
            tutStep={tutStep}
            advanceTut={advanceTut}
          />
        )}
        {liveStop && !repository && liveStop.round.phase === "rating" && (
          <DuelSection
            key={liveStop.round.id}
            roundId={liveStop.round.id}
            board={liveStop.props}
            participantId={participantId}
            remainingSec={clock.remaining}
            onChanged={refresh}
            onVoted={() => pushOptIn.maybeOffer()}
            advanceTut={advanceTut}
          />
        )}
        {!pending && !liveStop && leafProp != null && !repository && (
          <LeafComposer
            propId={leafProp}
            participantId={participantId}
            windowOpen={leafWindowOpen}
            onChanged={refresh}
            tutStep={tutStep}
            advanceTut={advanceTut}
          />
        )}
        </div>
      </div>

      {/* The Vote FAB (repository) — page-level so it never remounts on
          navigation, and ALWAYS present (even while voting) so the duel is a
          mode you can leave freely. It glows when there are ideas to weigh in
          on — an invitation, not a gate. Adding an opinion is the composer at
          the top of the list, not a FAB. */}
      {repository && (
        <ActionFabs
          roundId={liveStop?.round.id ?? null}
          participantId={participantId}
          hasPair={hasPair}
          refreshKey={`${tab}:${liveStop?.props.length ?? 0}`}
          voteActive={voteActive}
          onVote={() => {
            // Entering the duel is the moment the core idea (crowd-judged, no
            // fixed axis) becomes real — teach it the first time, imperatively
            // (no liveStop-dependent effect above the boot early-returns).
            if (!voteActive && hasPair) fireReveal("duel");
            setTab(voteActive ? "replies" : "vote");
          }}
          tutVote={tutStep === "vote"}
        />
      )}
      <PushOptInCard
        s={pushOptIn}
        prompt="Get a ping when new opinions land here?"
      />
      {justFinishedTut && (
        <div className={css.tutDoneToast} role="status">
          <span className={css.tutDoneTitle}>🎉 You&apos;ve got it</span>
          <span className={css.tutDoneSub}>
            Add ideas, vote on the best, watch the winners rise. Have at it.
          </span>
        </div>
      )}
      {inboxOpen && (
        <WatchInbox
          items={watches.inbox}
          onClose={() => setInboxOpen(false)}
          onOpen={(propId) => {
            setInboxOpen(false);
            watches.markSeen(propId); // opening it clears its new-reply count
            // Jump straight into the watched opinion's thread by pre-committing
            // its root→target path, same as a deep-link.
            getPropositionPath(propId)
              .then((path) => {
                if (path.length) applyPath(path);
                window.scrollTo(0, 0);
              })
              .catch(() => {});
          }}
        />
      )}
      {conceptOpen && <ConceptSheet onClose={() => setConceptOpen(false)} />}
    </div>
  );
}
