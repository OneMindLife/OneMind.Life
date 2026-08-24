"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { QRCodeSVG } from "qrcode.react";
import {
  submitProposition,
  getPriorPairwiseVotes,
  submitPairwiseComparison,
  submitPairwiseSkip,
  markRatingComplete,
  getRoundScores,
  getVoterCount,
  loadGlobalWinners,
  generateOptions,
  propContent,
  DuplicatePropositionError,
  type Bootstrap,
  type PriorVote,
} from "@/lib/onemind/chat";
import {
  nextPair,
  type MatchObjective,
  type MatchPair,
  type Rateable,
} from "@/lib/onemind/matchPairSelector";
import { track } from "@/lib/onemind/analytics";
import { isTelegramContext, telegramWebApp, telegramInviteLink, shareViaTelegram } from "@/lib/telegram";
import {
  deriveClock,
  formatClock,
  proposingBar,
  phaseLabel,
  PROPOSING_MIN_TAKES,
  pickStarters,
  voteProgress,
  hueFor,
  winnerTimeParts,
  type GlobalWinner,
} from "@/lib/onemind/globalChat";
import { useI18n, preferredLang, type Lang } from "@/lib/i18n";
import LangToggle from "../../components/LangToggle";
import s from "./GlobalChat.module.css";

/// Compose the localized "when this won" label from the structured parts + the
/// viewer's locale, evaluated against the live `now` so it ages without a
/// refetch. Empty string when there is no valid timestamp (card shows no time).
function winnerTimeLabel(
  iso: string | null,
  now: Date,
  lang: Lang,
  t: (key: string, params?: Record<string, string | number>) => string,
): string {
  const parts = winnerTimeParts(iso, now);
  if (!parts) return "";
  if (parts.kind === "now") return t("room.timeNow");
  if (parts.kind === "minsAgo") return t("room.timeMinsAgo", { n: parts.n });
  const loc = lang === "es" ? "es" : "en-US";
  const time = new Date(parts.iso).toLocaleTimeString(loc, {
    hour: "numeric",
    minute: "2-digit",
  });
  if (parts.kind === "today") return t("room.timeToday", { time });
  if (parts.kind === "yesterday") return t("room.timeYesterday", { time });
  const date = new Date(parts.iso).toLocaleDateString(loc, {
    month: "short",
    day: "numeric",
  });
  return t("room.timeDated", { date, time });
}

/// The continuous, single-screen Global Chat ("the room speaks"). A permanent
/// feed of past winning takes + a live staging block for the current round,
/// with a clock-driven dock (composer while proposing, duel while voting). No
/// host controls, no AI — the 12h clock is the host. See
/// docs/design/global-chat/README.md.
export default function GlobalChat({
  data,
  code,
  presence,
  onChanged,
}: {
  data: Bootstrap;
  code: string;
  presence: number;
  onChanged: () => Promise<void> | void;
}) {
  const { t, lang, setLang } = useI18n();
  const round = data.current_round;
  const me = data.my_participant;
  const myId = me?.id ?? null;
  const chatId = data.chat.id;
  // Only translation-enabled chats (the family room) open in the device/
  // persisted language; the rest of the app stays English. Opt in once on mount.
  const translationsEnabled = Boolean(
    (data.chat as Record<string, unknown>).translations_enabled,
  );
  useEffect(() => {
    if (translationsEnabled) setLang(preferredLang());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [translationsEnabled]);
  const roundId = round?.id ?? null;
  const phase = round?.phase;
  const isProposing = phase === "proposing";
  const isVoting = phase === "rating";
  const objective = ((data.chat.match_objective as string) ||
    "winner_only") as MatchObjective;
  const submitted = (data.my_propositions?.length ?? 0) > 0;
  // Optional seed question — ONLY a real initial_message, never the chat name
  // (GLOBAL has none → no question card, just the open room).
  const question = ((data.chat as Record<string, unknown>)
    .initial_message_translated ||
    (data.chat as Record<string, unknown>).initial_message ||
    "") as string;

  // ── Local one-second clock. `now` re-syncs from the server (phase_ends_at) on
  // every bootstrap refresh; between refreshes it ticks locally so the fill
  // drains smoothly.
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const iv = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(iv);
  }, []);
  const clock = useMemo(() => deriveClock(round, now), [round, now]);

  // ── Winners chain (permanent history). Refetched on mount and whenever the
  // round rolls over (a new round id ⇒ the previous round just sealed a winner).
  const [winners, setWinners] = useState<GlobalWinner[]>([]);
  const seenIds = useRef<Set<number>>(new Set());
  const initialised = useRef(false);
  const [freshId, setFreshId] = useState<number | null>(null);
  const [reveal, setReveal] = useState(false);
  const [celebrate, setCelebrate] = useState<{ mine: boolean } | null>(null);
  const [shareWin, setShareWin] = useState<GlobalWinner | null>(null);
  // Invite bottom-sheet open state. Lifted to the .wrap root (not inside the
  // header) so the scrim's absolute inset:0 sizes to the full column, not the
  // header's positioned box.
  const [inviteOpen, setInviteOpen] = useState(false);

  // ── "Follow the channel" retention nudge: for Telegram users only, AFTER they
  // participate (submitted a take), a one-time dismissible prompt to follow
  // @onemind_life — the broadcast channel that pulls them back each phase. Web
  // users get web-push instead, so it's Telegram-gated. Dismissal persists.
  const [followDismissed, setFollowDismissed] = useState(false);
  useEffect(() => {
    try {
      if (localStorage.getItem("om_follow_dismissed") === "1") setFollowDismissed(true);
    } catch { /* private mode */ }
  }, []);
  const showFollow = submitted && !followDismissed && isTelegramContext();

  // ── Entrance choreography ("the room comes alive"): once per mount the
  // .intro class stagger-rises the feed children + dock via CSS, then clears.
  // Purely visual (opacity/transform) — interactivity is never delayed.
  const [intro, setIntro] = useState(true);
  useEffect(() => {
    const t = setTimeout(() => setIntro(false), 1600);
    return () => clearTimeout(t);
  }, []);

  // ── Arrival coach: a TRANSIENT spotlight, not a permanent element. It fades
  // in AFTER the room has settled (so the eye lands on it last), dims everything
  // else for a beat so it reads on a busy screen, holds, then fades — leaving
  // the screen exactly as clean as before. Dismissed the instant the user
  // touches anything.
  //
  // It states the MISSION rather than the next tap, so the first thing you read
  // in the room is why the room exists. The propose/vote split is kept only as
  // the TRIGGER (each phase has its own timing); the copy is identical.
  // Rendered CENTRED on the viewport (2026-08-11) — see .coachFloat.
  const [coach, setCoach] = useState<null | "propose" | "vote">(null);
  const coachSeen = useRef<{ propose: boolean; vote: boolean }>({ propose: false, vote: false });
  useEffect(() => {
    if (coachSeen.current.propose || !isProposing || submitted) return;
    coachSeen.current.propose = true;
    try {
      if (sessionStorage.getItem(`gcoach:${chatId}`)) return;
    } catch {
      /* storage blocked — just show it */
    }
    const show = setTimeout(() => {
      setCoach("propose");
      try {
        sessionStorage.setItem(`gcoach:${chatId}`, "1");
      } catch {
        /* best-effort */
      }
    }, 1900); // after the 1600ms intro choreography settles
    return () => clearTimeout(show);
  }, [isProposing, submitted, chatId]);
  useEffect(() => {
    if (coachSeen.current.vote || !isVoting) return;
    coachSeen.current.vote = true;
    const show = setTimeout(() => setCoach("vote"), 700);
    return () => clearTimeout(show);
  }, [isVoting]);
  // Auto-fade once it has had a beat to register.
  useEffect(() => {
    if (!coach) return;
    const hide = setTimeout(() => setCoach(null), 2800);
    return () => clearTimeout(hide);
  }, [coach]);

  // Runs after mount (second wave) and on every round roll-over: fetches the
  // permanent winners chain and marks a just-posted winner "fresh" once.
  const refetchWinners = useCallback(async () => {
    try {
      const w = await loadGlobalWinners(chatId, myId, lang);
      setWinners((prev) => {
        // Mark a just-posted winner "fresh" (gold shine) once, after the first
        // load — a new id we've never rendered and the list grew.
        if (initialised.current && w.length > prev.length) {
          const latest = w[w.length - 1];
          if (latest && !seenIds.current.has(latest.id)) {
            setFreshId(latest.id);
            setReveal(true);
            // Payoff moment: a centered toast ONLY when the human's OWN take
            // just won (the brag-worthy, shareable beat). The generic "The room
            // converged" toast that fired for everyone else was removed
            // 2026-08-11 — it interrupted every round for people it wasn't
            // about. The winner still lands in the feed with the gold shine.
            if (latest.mine) {
              setCelebrate({ mine: true });
              setTimeout(() => setCelebrate(null), 2900);
            }
            setTimeout(() => setFreshId(null), 2000);
            setTimeout(() => setReveal(false), 2400);
          }
        }
        w.forEach((x) => seenIds.current.add(x.id));
        initialised.current = true;
        return w;
      });
    } catch {
      /* transient — next roll-over / mount retries */
    }
  }, [chatId, myId, lang]);

  useEffect(() => {
    void refetchWinners();
  }, [refetchWinners, roundId]);

  // ── Staging takes (current round). Open board: everyone reads the takes as
  // they land (raw text only — no vote/popularity signals, so no herding); the
  // ask is "add yours to shape the winner", not "post to unlock".
  const takes = useMemo(() => {
    const props = data.propositions ?? [];
    return props.map((p, i) => ({
      id: p.id,
      text: propContent(p),
      mine: p.participant_id === myId,
      hue: p.participant_id === myId ? "h0" : hueFor(i),
      createdAt: p.created_at ?? null,
    }));
  }, [data.propositions, myId]);

  // ── Funnel: one room-view per mount. Winners load async, so `winners` may
  // still be 0 here — acceptable; `takes_in` reflects the bootstrap snapshot.
  const viewedRef = useRef(false);
  useEffect(() => {
    if (viewedRef.current) return;
    viewedRef.current = true;
    track("global_room_viewed", {
      chat_id: String(chatId),
      phase: phase ?? "none",
      takes_in: takes.length,
      winners: winners.length,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Auto-scroll the record (permanent chat: winners / vote duel) to newest.
  const feedRef = useRef<HTMLDivElement | null>(null);
  const lastLen = useRef(0);
  useEffect(() => {
    const el = feedRef.current;
    if (!el) return;
    const len = winners.length;
    if (len >= lastLen.current) {
      requestAnimationFrame(() => {
        el.scrollTop = el.scrollHeight;
      });
    }
    lastLen.current = len;
  }, [winners.length, isVoting]);

  // ── Auto-scroll the LIVE FEED (current round's incoming messages) to newest,
  // so the latest take always sits just above the composer as they land live.
  const liveRef = useRef<HTMLDivElement | null>(null);
  const lastTakes = useRef(0);
  useEffect(() => {
    const el = liveRef.current;
    if (!el) return;
    if (takes.length >= lastTakes.current) {
      requestAnimationFrame(() => {
        el.scrollTop = el.scrollHeight;
      });
    }
    lastTakes.current = takes.length;
  }, [takes.length, submitted]);

  return (
    <div
      className={`${s.wrap} ${reveal ? s.reveal : ""} ${intro ? s.intro : ""} ${
        coach === "propose" ? s.coaching : ""
      }`}
      onPointerDownCapture={() => {
        if (coach) setCoach(null);
      }}
    >
      <div className={s.ambient} />
      <div className={s.grain} />

      <header className={s.gh}>
        <div className={s.ghTop}>
          <div className={s.brand}>
            {/* Real OneMind logomark (repo asset). */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={s.logomark} src="/icon-192.png" alt="OneMind" />
            <span>OneMind</span>
          </div>
          <div className={s.ghActions}>
            {/* The language toggle only appears where switching does something:
                chats with translation enabled (the family room), not GLOBAL. */}
            {translationsEnabled && <LangToggle />}
            <div className={`${s.presence} presence live`}>
              <span className={s.pdot} />
              <span className={s.pcount}>{Math.max(1, presence)}</span>
              <span>{t("room.here")}</span>
            </div>
            <button
              className={s.invite}
              type="button"
              onClick={() => {
                setInviteOpen(true);
                track("global_invite_opened", { chat_id: String(chatId) });
              }}
            >
              <svg viewBox="0 0 14 14">
                <path
                  d="M5 9l4-4M6 3.5l1-1a2.5 2.5 0 013.5 3.5l-1 1M8 10.5l-1 1A2.5 2.5 0 013.5 8l1-1"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
              {t("room.invite")}
            </button>
          </div>
        </div>
      </header>

      {/* Retention nudge (Telegram, post-participation): follow the channel that
          pings the daily winner + each new round → pulls them back. */}
      {showFollow && (
        <div className={s.followBar}>
          <span className={s.followText}>
            {t("room.followPre")}
            <b>@onemind_life</b>
            {t("room.followPost")}
          </span>
          <button
            type="button"
            className={s.followGo}
            onClick={() => {
              const app = telegramWebApp();
              if (app?.openTelegramLink) app.openTelegramLink("https://t.me/onemind_life");
              else window.open("https://t.me/onemind_life", "_blank", "noopener");
              try {
                localStorage.setItem("om_follow_dismissed", "1");
              } catch { /* private mode */ }
              setFollowDismissed(true);
              track("global_channel_follow_click", { chat_id: String(chatId) });
            }}
          >
            {t("room.followGo")}
          </button>
          <button
            type="button"
            className={s.followX}
            aria-label={t("room.dismiss")}
            onClick={() => {
              try {
                localStorage.setItem("om_follow_dismissed", "1");
              } catch { /* private mode */ }
              setFollowDismissed(true);
            }}
          >
            ✕
          </button>
        </div>
      )}

      {/* ── The record window: the permanent chat — the winning messages the
          room has kept. Framed like an instrument panel (gold-keyed = decided),
          parallel to the live-feed window below (blue = active this round). */}
      <div className={s.recordWin}>
        <div className={s.feed} ref={feedRef} data-screen-label="Global chat">
        {question && (
          <div className={`${s.msg} ${s.seedMsg}`}>
            <div className={s.body}>
              <div className={s.bubble}>
                <div className={s.take}>{question}</div>
              </div>
            </div>
          </div>
        )}

        {winners.map((w) => (
          <div
            key={w.id}
            data-testid="global-winner"
            className={`${s.msg} ${w.id === freshId ? s.fresh : ""}`}
          >
            <div className={s.body}>
              <div className={s.bubble}>
                <div className={s.take}>{w.text}</div>
                {/* Just the timestamp. The competition stats (beat N takes /
                    N voters decided) and the share button were removed — the
                    room reads as a group chat, not a contest scoreboard. */}
                {(() => {
                  const label = winnerTimeLabel(w.timeIso, now, lang, t);
                  return label ? (
                    <div className={s.foot}>
                      <span className={s.time}>{label}</span>
                    </div>
                  ) : null;
                })()}
              </div>
            </div>
          </div>
        ))}

        {/* Record empty-state — names the top zone as the permanent chat (where
            winning messages land), distinct from the live feed below. */}
        {isProposing && winners.length === 0 && (
          <div className={s.recordEmpty}>{t("room.recordEmpty")}</div>
        )}

        </div>
      </div>

      {/* Voting = the duel + post-ballot leaderboard, its OWN fixed-height window
          (VotingStage's root is .voteWin) — same slot/frame/height as the live
          feed below, so the "action window" reads consistently across phases. */}
      {isVoting && (
        <VotingStage data={data} objective={objective} onChanged={onChanged} />
      )}

      {/* ── Live feed: a fixed-height, scrollable WINDOW of the current round's
          incoming messages, sitting right above the composer. Deliberately
          distinct from the permanent chat/record above — this is the churny
          collection of takes people are submitting now, updating live. Cold
          arrivals were bouncing off an empty composer-only screen (IG ad 0/38,
          2026-07-20); the live window gives social proof + models what to post.
          Raw text only (no vote counts) so there's no herding. */}
      {/* Gate: the whole live-feed window is hidden until you've posted this
          round (reduces anchoring + keeps the pre-post UI clean). Cold arrivals
          still have the record's winner above as social proof. */}
      {isProposing && submitted && (
        <div className={s.liveFeed}>
          <div className={s.liveHead}>
            <span className={s.liveDot} />
            {t("room.liveFeed")}
            <span className={s.liveCount}>{takes.length}</span>
          </div>
          <div className={s.liveScroll} ref={liveRef}>
            {takes.length === 0 ? (
              <div className={s.liveEmpty}>{t("room.noMessages")}</div>
            ) : (
              takes.map((tk) => (
                <div
                  key={tk.id}
                  data-testid="global-take"
                  className={`${s.liveMsg} ${tk.mine ? s.liveMine : ""}`}
                >
                  <span className={s.liveText}>{tk.text}</span>
                  {tk.mine && <span className={s.liveYou}>{t("room.you")}</span>}
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* Composer pinned at the BOTTOM (chat convention). ONE take per person per
          proposing phase: once submitted, the composer is replaced by the live
          feed (which renders on `submitted`), so the textfield disappears. */}
      {isProposing && round && me && !submitted && (
        <div className={s.composerBar}>
          <Composer
            roundId={round.id}
            participantId={me.id}
            chatId={chatId}
            roundNo={(round.custom_id as number) || 1}
            history={[question, ...winners.map((w) => w.text)].filter(
              (t) => t.trim().length > 0,
            )}
            boardTexts={takes.map((t) => t.text)}
            onChanged={onChanged}
          />
        </div>
      )}

      {/* The dock is now just the persistent phase timer — the action (compose /
          vote) lives inline in the feed above. */}
      <div className={s.dock}>
        {isProposing &&
          (() => {
            // Below proposing_minimum the timer silently extends, so a
            // countdown would be a lie — show the takes-threshold goal
            // instead (fill = progress toward the minimum, not time).
            const bar = proposingBar(takes.length, clock);
            return (
              <div className={s.pbar}>
                <div className={s.pbarFill} style={{ width: `${bar.pct}%` }} />
                <div className={s.pbarRow}>
                  {/* The cadence lives in the label so it is visible in BOTH the
                      cold-start goal state AND the live countdown. Derived from
                      the chat, not hardcoded: the room's phases went 12h → 60s
                      when it became a scheduled live event, and a stale "12h"
                      here would be the one thing on screen telling the user the
                      round is slow while it ticks every minute. */}
                  <span className={s.pbarLabel}>
                    {t("room.proposingPhase", {
                      label: phaseLabel(
                        Number(
                          (data.chat as Record<string, unknown>)
                            .proposing_duration_seconds,
                        ),
                      ),
                    })}
                  </span>
                  <span className={s.pbarTime}>
                    {bar.mode === "goal" ? (
                      // Below the 2-take minimum the 12h timer silently extends,
                      // so show the honest blocker (not a countdown that resets).
                      t("room.takesGoal", {
                        n: takes.length,
                        min: PROPOSING_MIN_TAKES,
                      })
                    ) : (
                      <>
                        {t("room.votingOpensInPre")}
                        <b>{formatClock(clock.remaining)}</b>
                      </>
                    )}
                  </span>
                </div>
              </div>
            );
          })()}
        {isVoting &&
          (() => {
            // The rating timer only advances at expiry once ≥1 voter has
            // FINISHED a ballot (matchesTimerMinimumMet in process-timers);
            // below that it silently extends. Detect that state — the clock
            // hit 0, or the server window outgrew the configured duration
            // (phase-start round-up adds ≤60s, so +90s means an extension
            // happened) — and say what the round actually waits for instead
            // of a countdown that resets.
            const configured =
              Number((data.chat as Record<string, unknown>).rating_duration_seconds) || 120;
            const stalled = clock.remaining === 0 || clock.duration > configured + 90;
            return (
              <div className={`${s.pbar} ${s.voting}`}>
                <div className={s.pbarFill} style={{ width: `${clock.pct}%` }} />
                <div className={s.pbarRow}>
                  <span className={s.pbarLabel}>{t("room.votingLabel")}</span>
                  <span className={s.pbarTime}>
                    {stalled ? (
                      <>
                        {t("room.votingStalledPre")}
                        <b>{t("room.votingStalledStrong")}</b>
                      </>
                    ) : (
                      <>
                        {t("room.roundEndsInPre")}
                        <b>{formatClock(clock.remaining)}</b>
                      </>
                    )}
                  </span>
                </div>
              </div>
            );
          })()}
        {!isProposing && !isVoting && (
          <div className={s.dockStatus}>
            {t("room.betweenPre")}
            <b>{t("room.betweenStrong")}</b>
          </div>
        )}
      </div>

      {/* The mission line, centred on the viewport. Same copy in both phases,
          matching the landing page. The phase guards stay so a stale coach
          can't outlive the state that triggered it (e.g. you submit while
          it's on screen). */}
      {((coach === "propose" && isProposing && !submitted) ||
        (coach === "vote" && isVoting)) && (
        <div className={s.coachFloat} aria-live="polite">
          <span>
            {t("room.coachPre")}
            <b>{t("room.coachStrong")}</b>
          </span>
        </div>
      )}

      {/* Only fires when YOUR take won — see the guard in refetchWinners. */}
      {celebrate && (
        <div className={s.celebrate} aria-live="polite">
          <div className={`${s.celebrateCard} ${s.celebrateMine}`}>
            <span className={s.celebrateBig}>{t("room.celebrateWonBig")}</span>
            <span className={s.celebrateSub}>{t("room.celebrateWonSub")}</span>
          </div>
        </div>
      )}

      {inviteOpen && <InviteSheet code={code} onClose={() => setInviteOpen(false)} />}
      {shareWin && (
        <WinnerShareSheet
          winner={shareWin}
          code={code}
          chatId={chatId}
          onClose={() => setShareWin(null)}
        />
      )}
    </div>
  );
}

// ── Composer (proposing dock) ────────────────────────────────────────────────

function Composer({
  roundId,
  participantId,
  chatId,
  roundNo,
  history,
  boardTexts,
  onChanged,
}: {
  roundId: number;
  participantId: number;
  chatId: number;
  roundNo: number;
  history: string[];
  boardTexts: string[];
  onChanged: () => Promise<void> | void;
}) {
  const { t } = useI18n();
  // Rotating composer invitations, localized. Keyed on `t` so a language switch
  // swaps the placeholder live (t changes identity when `lang` changes).
  const placeholders = useMemo(
    () => [
      t("room.ph0"),
      t("room.ph1"),
      t("room.ph2"),
      t("room.ph3"),
      t("room.ph4"),
    ],
    [t],
  );
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [phIdx, setPhIdx] = useState(0);
  const taRef = useRef<HTMLTextAreaElement | null>(null);
  // Funnel: first focus / first non-empty keystroke, once per Composer mount.
  const focusTracked = useRef(false);
  const typedTracked = useRef(false);

  // ── AI starter takes (WRITING ASSIST only — the AI has no seat, no vote,
  // and nothing enters the round unless a human taps, edits, and sends).
  // Generated per visitor (variety across users counters homogenization),
  // cached per round in sessionStorage so reloads don't re-bill. Chips that
  // match a take already on the board are filtered out (pickStarters).
  const [starterPool, setStarterPool] = useState<string[]>([]);
  const starterUsed = useRef<string | null>(null);
  const startersShownTracked = useRef(false);
  useEffect(() => {
    let alive = true;
    const key = `gstarters:${roundId}`;
    try {
      const cached = sessionStorage.getItem(key);
      if (cached) {
        setStarterPool(JSON.parse(cached) as string[]);
        return;
      }
    } catch {
      /* storage unavailable — fall through to a fresh fetch */
    }
    (async () => {
      // round_id → the per-round shared pool (one LLM call per round; cached
      // server-side, so everyone after the round's first visitor gets chips
      // instantly). The full conversation `history` drives it: the model reads
      // the thread and proposes the single best next take — an answer to the
      // open question, a counterpoint, or the next thing worth deciding. No Q/A
      // mode, no forced "?". [] on any failure.
      const nominal = history[history.length - 1] || "the conversation";
      const raw = await generateOptions(nominal, 6, roundId, history);
      if (!alive || raw.length === 0) return;
      setStarterPool(raw);
      try {
        sessionStorage.setItem(key, JSON.stringify(raw));
      } catch {
        /* best-effort cache */
      }
    })();
    return () => {
      alive = false;
    };
    // `history` is included so the first cache-populating call for a round runs
    // with the real loaded thread (winners load async) — not an empty one. The
    // per-round server cache dedupes any repeat call. history.join() keys the
    // effect on content, not array identity.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roundId, history.join("")]);

  // Shuffle the shared pool once per visitor (Fisher–Yates) so a round-level
  // cache still yields different chips per person, then filter against the
  // board. Deliberately NOT re-shuffled per render.
  const shuffled = useMemo(() => {
    const a = [...starterPool];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }, [starterPool]);
  // One AI nudge, not a menu — a shorter dock lets the feed (and the question
  // we're answering) breathe up into view. Choice-paralysis down, propose up.
  const starters = useMemo(
    () => pickStarters(shuffled, boardTexts, 1),
    [shuffled, boardTexts],
  );
  // AI suggestions removed — the composer is just the textfield.
  const showStarters = false && starters.length > 0 && draft.trim().length === 0 && !busy;
  useEffect(() => {
    if (!showStarters || startersShownTracked.current) return;
    startersShownTracked.current = true;
    track("global_starters_shown", { chat_id: String(chatId), count: starters.length });
  }, [showStarters, starters.length, chatId]);

  function tapStarter(text: string, index: number) {
    starterUsed.current = text;
    setDraft(text);
    track("global_starter_tapped", { chat_id: String(chatId), index });
    requestAnimationFrame(() => {
      taRef.current?.focus();
      grow();
    });
  }

  // Rotate the invitation placeholder every ~4s while the draft is empty.
  useEffect(() => {
    if (draft.trim()) return;
    const iv = setInterval(
      () => setPhIdx((i) => (i + 1) % placeholders.length),
      4000,
    );
    return () => clearInterval(iv);
  }, [draft, placeholders.length]);

  function grow() {
    const el = taRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(88, el.scrollHeight)}px`;
  }

  // No enforcement: people can submit anything. The Q/A alternation is only a
  // soft nudge via the AI starters (question mode suggests questions, answer
  // mode suggests answers) — never a gate on what a person types.
  const canSend = draft.trim().length > 0 && !busy;

  async function submit() {
    const content = draft.trim();
    if (!content || busy) return;
    setBusy(true);
    setErr(null);
    try {
      await submitProposition(roundId, participantId, content);
      track("proposition_submitted", {
        chat_id: String(chatId),
        round_number: roundNo,
        content_length: content.length,
        surface: "global",
        starter_used: starterUsed.current != null,
        starter_edited: starterUsed.current != null && content !== starterUsed.current,
      });
      setDraft("");
      await onChanged();
    } catch (e) {
      setErr(
        e instanceof DuplicatePropositionError
          ? t("room.errDuplicate")
          : t("room.errPost"),
      );
      setBusy(false);
    }
  }

  return (
    <>
      {showStarters && (
        <div className={s.optStack}>
          {/* AI starters render as the same stacked cards the room votes on —
             tap fills the composer below (the final "write your own" card), so
             the whole dock reads as one uniform pick list. */}
          {starters.map((opt, i) => (
            <button
              key={opt}
              className={s.optCard}
              type="button"
              onClick={() => tapStarter(opt, i)}
            >
              <div className={s.optText}>{opt}</div>
              <div className={s.optPick}>{t("room.useThis")}</div>
            </button>
          ))}
        </div>
      )}
      <div className={`${s.composer} ${showStarters ? s.composerLast : ""}`}>
        <textarea
          ref={taRef}
          data-testid="global-composer"
          rows={1}
          placeholder={placeholders[phIdx]}
          value={draft}
          disabled={busy}
          maxLength={600}
          onInput={grow}
          onFocus={() => {
            if (focusTracked.current) return;
            focusTracked.current = true;
            track("global_composer_focused", { chat_id: String(chatId) });
          }}
          onChange={(e) => {
            const v = e.target.value;
            if (!typedTracked.current && v.trim().length > 0) {
              typedTracked.current = true;
              track("global_composer_typed", { chat_id: String(chatId) });
            }
            if (v.trim().length === 0) starterUsed.current = null;
            setDraft(v);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void submit();
            }
          }}
        />
        <button
          className={s.send}
          type="button"
          onClick={submit}
          disabled={!canSend}
          aria-label={t("room.send")}
        >
          <svg viewBox="0 0 18 18">
            <path d="M3 9h11M10 4l5 5-5 5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </div>
      {err ? (
        <div className={s.dockHint} style={{ color: "var(--ink-1)" }}>
          {err}
        </div>
      ) : (
        <div className={s.dockHint}>{t("room.dockHint")}</div>
      )}
    </>
  );
}

// ── Voting stage (duel) ──────────────────────────────────────────────────────

type VPhase =
  | { kind: "loading" }
  | { kind: "pair"; pair: MatchPair }
  | { kind: "nothing" }
  | { kind: "done" };

function VotingStage({
  data,
  objective,
  onChanged,
}: {
  data: Bootstrap;
  objective: MatchObjective;
  onChanged: () => Promise<void> | void;
}) {
  const { t } = useI18n();
  const round = data.current_round!;
  const me = data.my_participant!;
  const chatId = data.chat.id;

  // Conditional self-inclusion: never vote on your own idea — unless excluding
  // it leaves fewer than two (then your own joins the pool). Mirrors Voting.tsx.
  const rateable: Rateable[] = useMemo(() => {
    const props = data.propositions ?? [];
    const nonOwn = props.filter((p) => p.participant_id !== me.id);
    const votable = nonOwn.length >= 2 ? nonOwn : props;
    return votable.map((p) => ({ id: p.id, content: propContent(p) }));
  }, [data.propositions, me.id]);

  const contentById = useMemo(() => {
    const m = new Map<number, string>();
    (data.propositions ?? []).forEach((p) => m.set(p.id, propContent(p)));
    return m;
  }, [data.propositions]);

  const [votes, setVotes] = useState<PriorVote[]>([]);
  const [vphase, setVphase] = useState<VPhase>({ kind: "loading" });
  const [busy, setBusy] = useState(false);
  // Post-ballot payoff: the provisional standings + how many have voted. Fetched
  // once the user finishes (kind:"done") — safe to reveal then (no herding, their
  // ballot is already in). Scores are the live MOVDA global_score (kept fresh by
  // the every-minute recompute cron for rating-phase rounds).
  const [board, setBoard] = useState<{ id: number; text: string; score: number }[] | null>(null);
  const [voters, setVoters] = useState<number | null>(null);

  const advance = useCallback(
    async (current: PriorVote[]) => {
      const p = nextPair(rateable, current, objective);
      if (p) {
        setVphase({ kind: "pair", pair: p });
        return;
      }
      try {
        await markRatingComplete(round.id, me.id);
      } catch {
        /* idempotent */
      }
      track("global_vote_done", {
        chat_id: String(chatId),
        votes: current.length,
      });
      setVphase(rateable.length < 2 ? { kind: "nothing" } : { kind: "done" });
      await onChanged();
    },
    [rateable, objective, round.id, me.id, chatId, onChanged],
  );

  // Load prior votes + first pair once per round.
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const prior = await getPriorPairwiseVotes(round.id, me.id);
        if (!alive) return;
        setVotes(prior);
        await advance(prior);
      } catch {
        if (alive) setVphase({ kind: "done" });
      }
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [round.id]);

  // Once the ballot's done, show the provisional leaderboard + voter count and
  // keep it LIVE — re-poll every 60s (the MOVDA scores recompute server-side
  // every minute for rating-phase rounds, so the standings shift as more people
  // vote while this voter waits for the clock).
  useEffect(() => {
    if (vphase.kind !== "done") return;
    let alive = true;
    const load = async () => {
      try {
        const [scores, vc] = await Promise.all([
          getRoundScores(round.id),
          getVoterCount(round.id),
        ]);
        if (!alive) return;
        const ranked = (data.propositions ?? [])
          .map((p) => ({ id: p.id, text: propContent(p), score: scores.get(p.id) ?? 0 }))
          .sort((a, b) => b.score - a.score);
        setBoard(ranked);
        setVoters(vc);
      } catch {
        /* keep the last-good board (or the fallback copy) on a transient error */
      }
    };
    load();
    const iv = setInterval(load, 60_000);
    return () => {
      alive = false;
      clearInterval(iv);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [vphase.kind, round.id]);

  async function cast(winnerId: number, loserId: number, isTie: boolean) {
    if (busy || vphase.kind !== "pair") return;
    setBusy(true);
    try {
      await submitPairwiseComparison(round.id, me.id, winnerId, loserId, isTie);
      track("global_vote_cast", {
        chat_id: String(chatId),
        kind: isTie ? "tie" : "pick",
        index: votes.length,
        // Position-bias telemetry: ballot-order research predicts a 2-5pp
        // top-card advantage; log which card won so we can measure ours.
        winner_position: isTie
          ? undefined
          : winnerId === vphase.pair.top.id
            ? "top"
            : "bottom",
      });
      const next = [...votes, { winnerId, loserId, isTie, isSkip: false }];
      setVotes(next);
      await advance(next);
    } catch {
      /* leave the pair up; the user can retry */
    } finally {
      setBusy(false);
    }
  }

  async function skip(aId: number, bId: number) {
    if (busy || vphase.kind !== "pair") return;
    setBusy(true);
    try {
      await submitPairwiseSkip(round.id, me.id, aId, bId);
      track("global_vote_cast", {
        chat_id: String(chatId),
        kind: "skip",
        index: votes.length,
      });
      const next = [...votes, { winnerId: aId, loserId: bId, isTie: false, isSkip: true }];
      setVotes(next);
      await advance(next);
    } catch {
      /* retryable */
    } finally {
      setBusy(false);
    }
  }

  const { total, done } = voteProgress(rateable.length, votes.length);

  return (
    <div className={s.voteWin} data-testid="global-stage">
      {/* Pinned framing — stays static; only the body below scrolls. */}
      <div className={s.voteHead}>
        {vphase.kind === "done" ? (
          <span className={s.voteCheck}>✓</span>
        ) : (
          <span className={s.liveDot} />
        )}
        {vphase.kind === "done" ? t("room.voteDone") : t("room.voteNarrowing")}
        <span className={s.voteCount}>
          {vphase.kind === "done"
            ? voters != null
              ? t("room.votersCount", { n: voters })
              : ""
            : t("room.matchesCount", { done, total })}
        </span>
      </div>

      <div className={s.voteScroll}>
      {vphase.kind === "pair" && (
        <>
          <div className={s.duel}>
            <button
              className={s.prop}
              type="button"
              disabled={busy}
              onClick={() => cast(vphase.pair.top.id, vphase.pair.bottom.id, false)}
            >
              <div className={s.text}>
                {contentById.get(vphase.pair.top.id) ?? vphase.pair.top.content}
              </div>
              <div className={s.pick}>{t("room.backThis")}</div>
            </button>
            <button
              className={s.prop}
              type="button"
              disabled={busy}
              onClick={() => cast(vphase.pair.bottom.id, vphase.pair.top.id, false)}
            >
              <div className={s.text}>
                {contentById.get(vphase.pair.bottom.id) ?? vphase.pair.bottom.content}
              </div>
              <div className={s.pick}>{t("room.backThis")}</div>
            </button>
          </div>
          <div className={s.vrow}>
            <button
              className={s.equal}
              type="button"
              disabled={busy}
              onClick={() => cast(vphase.pair.top.id, vphase.pair.bottom.id, true)}
            >
              {t("room.tooClose")}
            </button>
            <button
              className={s.vskip}
              type="button"
              disabled={busy}
              onClick={() => skip(vphase.pair.top.id, vphase.pair.bottom.id)}
            >
              {t("room.skip")}
            </button>
          </div>
          <div className={s.vprog}>
            {Array.from({ length: total }, (_, i) => (
              <i key={i} className={i < done ? s.on : undefined} />
            ))}
          </div>
        </>
      )}

      {vphase.kind === "done" &&
        (board && board.length > 0 ? (
          <ol className={s.resultList}>
            {board.map((b, i) => (
              <li key={b.id} className={i === 0 ? s.resultLead : undefined}>
                <span className={s.resultRank}>{String(i + 1).padStart(2, "0")}</span>
                <span className={s.resultText}>{b.text}</span>
                <span className={s.resultScore}>{Math.round(b.score)}</span>
              </li>
            ))}
          </ol>
        ) : (
          <div className={s.resultFoot}>{t("room.countingRoom")}</div>
        ))}
      {vphase.kind === "nothing" && (
        <div className={s.stageEmpty}>
          <div className={s.eb}>{t("room.nothingTitle")}</div>
          <div className={s.es}>{t("room.nothingBody")}</div>
        </div>
      )}
      {vphase.kind === "loading" && (
        <div className={s.stageDone} style={{ color: "var(--ink-3)" }}>
          {t("room.loadingDuel")}
        </div>
      )}
      </div>

      {/* Pinned footer (results) — framing, stays put while the list scrolls. */}
      {vphase.kind === "done" && board && board.length > 0 && (
        <div className={s.voteFoot}>{t("room.provisional")}</div>
      )}
    </div>
  );
}

// ── Invite bottom-sheet ──────────────────────────────────────────────────────

/// The link a share/invite points at — the REAL arena, NEVER onemind.life (which
/// serves the Flutter app, not the never-empty wedge arena). Inside Telegram it's
/// the Mini App deep-link (opens the arena frictionlessly); on the web it's the
/// current origin, which IS the arena wherever this is served.
function arenaShareLink(code: string): string {
  if (isTelegramContext()) return telegramInviteLink(code);
  if (typeof window !== "undefined") return `${window.location.origin}/c/${code}`;
  return `https://onemind.life/c/${code}`; // SSR-only fallback; never rendered
}

function InviteSheet({ code, onClose }: { code: string; onClose: () => void }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  const tg = isTelegramContext();
  const shareUrl = arenaShareLink(code);
  const link = shareUrl.replace(/^https?:\/\//, "");

  async function copy() {
    track("quick_chat_share", { source: "global_invite" });
    // Inside Telegram: native "send to a chat" picker with the Mini App deep-link.
    if (tg && shareViaTelegram(shareUrl, t("room.inviteShareMsg"))) return;
    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard blocked */
    }
  }

  return (
    <div className={s.scrim} onClick={onClose}>
      <div className={s.sheet} onClick={(e) => e.stopPropagation()}>
        <h3>{t("room.inviteTitle")}</h3>
        <div className={s.sub}>{t("room.inviteSub")}</div>
        <div className={s.linkRow}>
          <div className={s.link}>{link}</div>
          <button className={s.copy} type="button" onClick={copy}>
            {tg ? t("room.share") : copied ? t("room.copied") : t("room.copy")}
          </button>
        </div>
        <div className={s.qr}>
          <QRCodeSVG value={shareUrl} size={130} level="M" />
        </div>
        <button className={s.done} type="button" onClick={onClose}>
          <u>{t("room.done")}</u>
        </button>
      </div>
    </div>
  );
}

// ── Winner share sheet ───────────────────────────────────────────────────────
// The #1 growth lever: every converged winner is a shareable card. Tapping a
// winner opens this — a preview of the result + a native share (mobile) or copy
// (desktop) of "the room decided ___, where do you stand? [link]". Each share
// recruits the next voter (distribution embedded in use).

function WinnerShareSheet({
  winner,
  code,
  chatId,
  onClose,
}: {
  winner: GlobalWinner;
  code: string;
  chatId: number;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  const tg = isTelegramContext();
  const shareUrl = arenaShareLink(code);
  const message = t("room.shareMessage", {
    text: winner.text,
    beat: winner.beat,
    voters: winner.voters,
    url: shareUrl,
  });

  async function share() {
    track("global_winner_shared", { chat_id: String(chatId), mine: winner.mine });
    // Inside Telegram: native "send to a chat" picker with the Mini App deep-link.
    if (tg && shareViaTelegram(shareUrl, t("room.shareTgMsg", { text: winner.text }))) {
      return;
    }
    const nav = typeof navigator !== "undefined" ? navigator : undefined;
    if (nav && typeof nav.share === "function") {
      try {
        await nav.share({ text: message, url: shareUrl });
        return;
      } catch {
        /* user cancelled or unsupported — fall through to copy */
      }
    }
    try {
      await navigator.clipboard.writeText(message);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      /* clipboard blocked */
    }
  }

  return (
    <div className={s.scrim} onClick={onClose}>
      <div className={s.sheet} onClick={(e) => e.stopPropagation()}>
        <h3>{winner.mine ? t("room.shareWonTitle") : t("room.shareDecidedTitle")}</h3>
        <div className={s.shareCard}>
          <div className={s.shareTake}>“{winner.text}”</div>
          <div className={s.shareMeta}>
            {t("room.shareMetaBeat")} <b>{winner.beat}</b> · <b>{winner.voters}</b>{" "}
            {t("room.shareMetaVoters")} · <span>{t("room.shareMetaStand")}</span>
          </div>
        </div>
        <div className={s.sub}>{t("room.shareSub")}</div>
        <button className={s.shareBtn} type="button" onClick={share}>
          {copied ? t("room.shareCopied") : t("room.shareBtn")}
        </button>
        <button className={s.done} type="button" onClick={onClose}>
          <u>{t("room.done")}</u>
        </button>
      </div>
    </div>
  );
}
