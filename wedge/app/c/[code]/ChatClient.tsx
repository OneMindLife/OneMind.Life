"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  getChatByCode,
  ensureParticipant,
  loadBootstrap,
  loadRoundHistory,
  startGroupChat,
  seedOptions,
  touchArenaPresence,
  type Bootstrap,
} from "@/lib/onemind/chat";
import { getScheduleState, type ScheduleState } from "@/lib/onemind/schedule";
import RoomClosed from "./RoomClosed";
import { usePresence } from "@/lib/onemind/usePresence";
import { chatQuestion } from "@/lib/onemind/chat";
import { useI18n } from "@/lib/i18n";
import { AppShell, Rail, ChatQuestion } from "../../components/ui";
import LangToggle from "../../components/LangToggle";
import SeedDialog from "./SeedDialog";
import Proposing from "./Proposing";
import GlobalChat from "./GlobalChat";
import LeaderChallenge from "./LeaderChallenge";
import Voting from "./Voting";
import Results from "./Results";
import NameGate, { hasNamed } from "./NameGate";

// How often the continuous arena tells the backend a human is present. Must stay
// well under the server's 2-minute cold threshold (migration 20260709220000) so a
// present viewer keeps the seat-fill bots running; tune both together.
const ARENA_HEARTBEAT_MS = 15_000;

type View =
  | { kind: "loading" }
  | { kind: "not_found" }
  | { kind: "needs_approval" }
  | { kind: "error"; message: string }
  | {
      kind: "closed";
      code: string;
      chatId: number;
      schedule: ScheduleState;
      lastWinner: string | null;
    }
  | { kind: "ready"; code: string; data: Bootstrap };

export default function ChatClient() {
  const { t, lang } = useI18n();
  const [view, setView] = useState<View>({ kind: "loading" });
  const [busy, setBusy] = useState(false);
  const chatIdRef = useRef<number | null>(null);
  // Whether the live-refresh poll should keep running (a ready, not-yet-ended
  // chat). Set after each load/refresh; read by the poll interval.
  const pollRef = useRef(false);
  // Latest chosen language. A fetch started under the old language can resolve
  // AFTER a language switch (the 3s poll especially) and clobber the freshly
  // loaded translated data — leaving the UI out of sync with the toggle. Each
  // fetch captures `lang` and drops its result if `langRef` has since changed.
  const langRef = useRef(lang);
  langRef.current = lang;

  // Full load: resolve code → view+join → bootstrap. Used on mount and after
  // the seed-gate start.
  const load = useCallback(async () => {
    // Works for both /c/<code> (new) and /join/<code> (legacy invite links).
    const m = window.location.pathname.match(/\/(?:c|join)\/([^/]+)/);
    const code = m && m[1] !== "_" ? decodeURIComponent(m[1]) : null;
    if (!code) {
      setView({ kind: "not_found" });
      return;
    }
    try {
      const chat = await getChatByCode(code);
      if (!chat) {
        setView({ kind: "not_found" });
        return;
      }
      // Scheduled rooms (the daily live event — docs/RETENTION_EXPERIMENT.md)
      // are gated BEFORE the join. Two reasons: outside the window there is
      // nothing to bootstrap, and a drive-by arrival at 3pm should not land a
      // participant row — the cohort we measure has to be the people who came
      // to the event.
      //
      // PERF: `get_chat_by_code` returns SETOF chats, so we already hold
      // schedule_type — and get_chat_schedule_state's own first branch is
      // "IF NOT FOUND OR schedule_type IS NULL -> (TRUE, NULL, NULL, tz)".
      // For every unscheduled room (i.e. all of them but the event room) the
      // round trip is therefore pure latency. Skip it and construct the same
      // answer locally. schedule_type is the real gate — NOT schedule_windows,
      // which is NULL-means-closed-forever.
      const scheduleType = (chat as unknown as { schedule_type?: string | null }).schedule_type ?? null;
      const schedule = scheduleType == null
        ? {
            isOpen: true,
            opensAt: null,
            closesAt: null,
            timezone:
              (chat as unknown as { schedule_timezone?: string | null }).schedule_timezone ?? "UTC",
          }
        : await getScheduleState(chat.id);
      if (!schedule.isOpen) {
        chatIdRef.current = chat.id;
        pollRef.current = false;
        // Winners come from get_round_history (DEFINER, public-readable), so
        // this works without being a participant.
        let lastWinner: string | null = null;
        try {
          const history = await loadRoundHistory(chat.id);
          const sealed = history.filter((h) => h.winner != null);
          lastWinner = sealed.length > 0 ? sealed[sealed.length - 1].winner : null;
        } catch {
          /* the closed screen stands on its own without it */
        }
        setView({ kind: "closed", code, chatId: chat.id, schedule, lastWinner });
        return;
      }

      // Sign-in + join — measured at ~570ms, the heaviest hop, and the one a
      // READER gets no value from: anonymous auth is its own round trip, then a
      // lookup, then an insert, all before anything renders.
      //
      // On a PUBLIC chat the bootstrap doesn't need it: get_chat_detail_bootstrap
      // grants v_can_view on `access_method = 'public'` alone. So fire the join
      // in parallel and paint from the public read. The catch is that the
      // per-round block (propositions / my_propositions / rating_progress) is
      // computed only when v_my_participant_id IS NOT NULL, so a pre-join
      // snapshot renders the permanent record but not the live round — we
      // re-bootstrap the moment the join lands to fill that in.
      //
      // A non-public (code) chat still has to join first: without a participant
      // row the RPC returns NULL outright.
      const isPublic =
        (chat as unknown as { access_method?: string }).access_method === "public";
      const joinPromise = ensureParticipant(chat);
      // Never let the parallel branch surface as an unhandled rejection.
      joinPromise.catch(() => null);

      // NOTE: prefetching the winners chain here (to overlap it with the
      // bootstrap) was tried and reverted on 2026-08-11. It LOOKED much worse
      // in testing (779ms → 2-5s), but those runs were measured on a saturated
      // dev box — the same batch recorded since_nav=17509ms with
      // chain_total=401ms, i.e. ~17s of client-side JS load before any of this
      // code ran, so the comparison was worthless. Server-side timings were
      // healthy throughout (get_round_history ~200-300ms).
      // So: UNPROVEN, not disproven. Reverted because the simpler code is the
      // better default until there's clean evidence. If real-traffic perf_logs
      // show load_global_winners dominating `messages_visible`, retry it — and
      // measure from a quiet machine or real devices, not from here.

      if (!isPublic) {
        const outcome = await joinPromise;
        if (outcome.status === "needs_approval") {
          setView({ kind: "needs_approval" });
          return;
        }
      }
      const data = await loadBootstrap(chat.id, lang);
      if (langRef.current !== lang) return; // a newer language took over
      if (!data) {
        setView({ kind: "error", message: t("chat.errCouldntLoad") });
        return;
      }
      chatIdRef.current = chat.id;
      pollRef.current = !data.chat.ended_at;
      setView({ kind: "ready", code, data });

      // The room is on screen; finish the join in the background and re-paint
      // with the per-round block once it lands. Timed separately (its own
      // correlation id) so it can't be confused with the blocking chain.
      if (isPublic) {
        void joinPromise
          .then(async (outcome) => {
            if (outcome.status === "needs_approval") {
              setView({ kind: "needs_approval" });
              return;
            }
            const withMe = await loadBootstrap(chat.id, lang);
            if (withMe && langRef.current === lang) {
              setView({ kind: "ready", code, data: withMe });
            }
          })
          .catch(() => { /* the poll re-syncs within 3s */ });
      }

    } catch (e) {
      setView({
        kind: "error",
        message: e instanceof Error ? e.message : t("common.somethingWrong"),
      });
    }
  }, [lang, t]);

  // Light refresh: re-fetch just the bootstrap for the already-resolved chat.
  // This is the live-update path — components call it after an action, and the
  // poll calls it on a timer so each client sees others' moves (new ideas, the
  // phase flip, vote counts, the final result) without a manual reload.
  const refresh = useCallback(async () => {
    const id = chatIdRef.current;
    if (id == null) return;
    try {
      const data = await loadBootstrap(id, lang);
      if (langRef.current !== lang) return; // a newer language took over
      if (!data) return;
      pollRef.current = !data.chat.ended_at;
      setView((v) => (v.kind === "ready" ? { ...v, data } : v));
    } catch {
      /* transient — the next tick retries */
    }
  }, [lang]);

  useEffect(() => {
    // Fetch-on-mount: load() only setState()s after awaits, not synchronously.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  // Live-update poll: every 3s, while the chat is live and the tab is visible,
  // pull a fresh snapshot. Stops once the chat has ended (pollRef) and pauses
  // on hidden tabs. Cheap (one bootstrap RPC); no realtime sockets.
  useEffect(() => {
    const iv = setInterval(() => {
      if (pollRef.current && document.visibilityState === "visible") {
        void refresh();
      }
    }, 3000);
    return () => clearInterval(iv);
  }, [refresh]);

  // Re-check a closed room on a slow timer as well as on the countdown hitting
  // zero (RoomClosed calls back). Belt-and-braces: a tab left open overnight,
  // or a clock that drifted, still opens on its own. 15s costs one tiny RPC.
  useEffect(() => {
    if (view.kind !== "closed") return;
    const iv = setInterval(() => {
      if (document.visibilityState === "visible") void load();
    }, 15_000);
    return () => clearInterval(iv);
  }, [view.kind, load]);

  // Arena presence heartbeat: for the continuous Global room ONLY (max_cycles ==
  // null, non-game), tell the backend a human is here so the seat-fill bots keep
  // running — and wake them if the room had gone cold (pause-when-empty). Fires
  // on entry and every ARENA_HEARTBEAT_MS while the tab is visible. Not called
  // for any other chat type.
  const continuousChatId =
    view.kind === "ready" &&
    view.data.chat.max_cycles == null &&
    view.data.chat.mode !== "game"
      ? view.data.chat.id
      : null;
  useEffect(() => {
    if (continuousChatId == null) return;
    const beat = () => {
      if (document.visibilityState === "visible") {
        void touchArenaPresence(continuousChatId);
      }
    };
    beat(); // warm immediately on entry
    const iv = setInterval(beat, ARENA_HEARTBEAT_MS);
    return () => clearInterval(iv);
  }, [continuousChatId]);

  // Live "who's here now" — one persistent presence channel for the whole chat
  // view (survives phase changes). Passed down to each live screen's rail.
  const presence = usePresence(view.kind === "ready" ? view.data.chat.id : null);

  // Scheduled room outside its window: the closed face, no join, no room.
  if (view.kind === "closed") {
    return (
      <RoomClosed
        chatId={view.chatId}
        state={view.schedule}
        lastWinner={view.lastWinner}
        onOpen={load}
      />
    );
  }

  // Continuous "Global" room (max_cycles == null, non-game): the clock-driven,
  // feed-based single-screen experience (chat code GLOBAL). Routes here BEFORE
  // the one-shot proposing/voting/results screens — the room never ends, so it
  // owns the whole surface. See GlobalChat + docs/design/global-chat/README.md.
  if (
    view.kind === "ready" &&
    view.data.chat.max_cycles == null &&
    view.data.chat.mode !== "game"
  ) {
    return (
      <GlobalChat
        data={view.data}
        code={view.code}
        presence={presence}
        onChanged={refresh}
      />
    );
  }

  // Game mode: everyone (host + participant) picks a real name on entry, once.
  // Gates before the seed/phase routing so authorship + the leaderboard are
  // meaningful. Decision mode never gates (hasNamed → true via the flag check).
  if (
    view.kind === "ready" &&
    view.data.chat.mode === "game" &&
    !hasNamed(view.data.chat.id)
  ) {
    return <NameGate chatId={view.data.chat.id} onDone={load} />;
  }

  // Host's first action on a not-yet-started chat: the seed-choice gate.
  // Game mode skips this entirely — it always gathers ideas from the group (the
  // round is started at creation), so the dialog never applies.
  if (
    view.kind === "ready" &&
    view.data.chat.mode !== "game" &&
    view.data.my_participant?.is_host &&
    !view.data.current_round &&
    !view.data.chat.ended_at
  ) {
    const chatId = view.data.chat.id;
    const fail = (e: unknown) =>
      setView({
        kind: "error",
        message: e instanceof Error ? e.message : t("chat.errCouldntStart"),
      });
    const startGroup = async () => {
      setBusy(true);
      try {
        // Convergence (confirmation_rounds_required=2) is fixed at creation for
        // both forks — nothing to flip here.
        await startGroupChat(chatId);
        await load();
      } catch (e) {
        fail(e);
      } finally {
        setBusy(false);
      }
    };
    const startSeed = async (opts: string[]) => {
      setBusy(true);
      try {
        await seedOptions(chatId, opts);
        await load();
      } catch (e) {
        fail(e);
      } finally {
        setBusy(false);
      }
    };
    return (
      <SeedDialog
        question={chatQuestion(view.data.chat)}
        busy={busy}
        onGroup={startGroup}
        onSeed={startSeed}
      />
    );
  }

  // Live chat: route by phase. Each phase component renders its own full screen.
  if (view.kind === "ready") {
    if (view.data.chat.ended_at)
      return <Results data={view.data} onReload={load} />;
    const round = view.data.current_round;
    const phase = round?.phase;
    const roundNo = (round?.custom_id as number) || 1;
    if (phase === "rating")
      return (
        <Voting
          data={view.data}
          code={view.code}
          presence={presence}
          onChanged={refresh}
        />
      );
    if (phase === "proposing")
      return roundNo >= 2 ? (
        <LeaderChallenge
          data={view.data}
          code={view.code}
          presence={presence}
          onChanged={refresh}
        />
      ) : (
        <Proposing
          data={view.data}
          code={view.code}
          presence={presence}
          onChanged={refresh}
        />
      );
    // No round yet for a non-host (host hasn't started): a brief waiting state.
    return (
      <AppShell>
        <Rail right={<LangToggle />} />
        <ChatQuestion q={chatQuestion(view.data.chat)} />
        <div className="center-status">
          <div className="small">{t("chat.waitingHost")}</div>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell>
      <Rail right={<LangToggle />} />
      {view.kind === "loading" && (
        <div className="center-status">
          <div className="small">{t("common.loading")}</div>
        </div>
      )}

      {view.kind === "not_found" && (
        <div className="center-status">
          <div className="big">{t("chat.notFoundTitle")}</div>
          <div className="small">{t("chat.notFoundBody")}</div>
          <a href="/create" className="btn" style={{ marginTop: 8 }}>
            {t("chat.startYourOwn")}
          </a>
        </div>
      )}

      {view.kind === "needs_approval" && (
        <div className="center-status">
          <div className="big">{t("chat.approvalTitle")}</div>
          <div className="small">{t("chat.approvalBody")}</div>
        </div>
      )}

      {view.kind === "error" && (
        <div className="center-status">
          <div className="big">{t("common.somethingWrong")}</div>
          <p className="err-text">{view.message}</p>
        </div>
      )}
    </AppShell>
  );
}
