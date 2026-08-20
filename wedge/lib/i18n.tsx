"use client";

// Lightweight EN/ES i18n for the app flow (create → chat → vote → results).
// The marketing/landing/SEO/blog pages stay English (separate SEO concern).
//
// User-generated content (the question + submitted ideas) is NOT translated
// here — that's done server-side (the `translations` table + the bootstrap /
// RPC `p_language_code`). This module only covers the fixed UI chrome and the
// language toggle. See lib/onemind/chat.ts for the content side.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type Lang = "en" | "es";
export const LANGS: Lang[] = ["en", "es"];
const STORAGE_KEY = "om_lang";

type Params = Record<string, string | number>;
type Entry = string | ((p: Params) => string);
type Dict = Record<string, Entry>;

// Small plural helper for the count-driven strings.
const plural = (n: number, one: string, many: string) => (n === 1 ? one : many);

const EN: Dict = {
  // ── shared chrome ──
  "common.back": "Back",
  "common.loading": "Loading…",
  "common.host": "You're the host",
  "common.somethingWrong": "Something went wrong",
  "common.tryAgain": "Something went wrong. Try again.",

  // ── create ──
  "create.eyebrow": "New decision",
  "create.q": "What are you deciding?",
  "create.help": "Your group will add ideas, then rank them to find the best one.",
  "create.placeholder": "e.g. Where should we hold the team offsite?",
  "create.cta": "Create a room to share",
  "create.creating": "Creating…",
  "create.consentPre": "By creating a room, you agree to our ",
  "create.terms": "Terms",
  "create.consentAmp": " & ",
  "create.privacy": "Privacy Policy",

  // ── ChatClient (load/join states) ──
  "chat.waitingHost": "Waiting for the host to start…",
  "chat.notFoundTitle": "Chat not found",
  "chat.notFoundBody": "This link is invalid or the chat is no longer available.",
  "chat.startYourOwn": "Start your own decision",
  "chat.approvalTitle": "Request to join",
  "chat.approvalBody": "This chat needs the host's approval. (Coming soon.)",
  "chat.errCouldntLoad": "Couldn't load this chat.",
  "chat.errCouldntStart": "Couldn't start the chat.",
  "chat.newRoom": "New room · just now",

  // ── SeedDialog ──
  "seed.title": "How should the ideas come in?",
  "seed.sub": "Everyone adds an idea, then the group ranks them — that's where OneMind is at its best.",
  "seed.fromGroup": "Get ideas from the group",
  "seed.starting": "Starting…",
  "seed.ai": "✦ Let AI suggest the options",
  "seed.aiThinking": "Thinking…",
  "seed.manual": "I'll add the options myself",
  "seed.reviewTitle": "Review the options",
  "seed.typeTitle": "Type the options to rank",
  "seed.reviewSub": "AI suggested these — edit or add any, then the group ranks them and confirms the winner.",
  "seed.typeSub": "Voting starts as soon as you're done — the group ranks them, then confirms the winner.",
  "seed.option": (p) => `Option ${p.n}`,
  "seed.addOption": "+ Add option",
  "seed.getIdeasInstead": "Get ideas instead",
  "seed.startVoting": "Start voting",

  // ── Proposing ──
  "prop.tagHost": "Proposing · add one idea",
  "prop.tagGuest": "Proposing · add your idea",
  "prop.yourIdeaIn": "✓ Your idea is in",
  "prop.placeholder": "Type your idea — one clear option…",
  "prop.addIdea": "Add idea",
  "prop.adding": "Adding…",
  "prop.errDuplicate": "Someone already added that idea.",
  "prop.errAdd": "Couldn't add your idea. Try again.",
  "prop.errStartVoting": "Couldn't start voting. Try again.",
  "prop.responses": (p) =>
    `${p.n} ${plural(Number(p.n), "response", "responses")} from your group`,
  "prop.revealed": "Revealed",
  "prop.hidden": "Hidden",
  "prop.revealedNote": "Revealed because you added yours — these get ranked next.",
  "prop.hiddenNote": "Add your own idea to reveal the rest.",
  "prop.you": " · you",
  "prop.waitHost": "Voting starts when the host's ready",
  "prop.startVoting": "Start voting",
  "prop.starting": "Starting…",
  "prop.readyNote": (p) =>
    `${p.n} ${plural(Number(p.n), "response", "responses")} in · start voting when ready`,
  "prop.needNote": (p) =>
    `${p.n} of ${p.need} responses · need ${p.need} to start voting`,

  // ── Voting ──
  "vote.prompt": (p) => `Round ${p.round} · which is better? Tap one.`,
  "vote.currentAnswer": "Current answer",
  "vote.alternative": "Alternative",
  "vote.keepIt": "Keep it",
  "vote.pick": "Pick",
  "vote.recording": "Recording…",
  "vote.equal": "Equal",
  "vote.skipPair": "Skip this pair",
  "vote.skipping": "Skipping…",
  "vote.nothingTitle": "Nothing to vote on yet",
  "vote.nothingBody": "To keep it fair, you don't vote on your own idea — and there aren't enough other ideas yet to compare. ",
  "vote.nothingHost": "Invite people so the group can vote.",
  "vote.nothingGuest": "Hang tight while more people join.",
  "vote.doneTitle": "Your votes are in.",
  "vote.doneHost": "Everyone's voting on the same pairs. End voting once enough people are done.",
  "vote.doneGuest": "Everyone's voting on the same pairs. The round finishes when the host ends voting.",
  "vote.tallying": "Tallying…",
  "vote.endNow": "End voting now",
  "vote.noVotesYet": "No votes cast yet — invite someone who can vote",
  "vote.doneCountReady": (p) => `${p.n} done voting · end when ready`,
  "vote.doneCountNeed": (p) =>
    `${p.n} of ${p.need} done voting · need ${p.need} to end`,
  "vote.waitHostEnds": "The round finishes when the host ends voting",
  "vote.errVote": "Couldn't record your vote.",
  "vote.errEnd": "Couldn't end voting. Try again.",
  "vote.errSkip": "Couldn't skip. Try again.",
  "vote.errLoad": "Couldn't load voting.",

  // ── LeaderChallenge ──
  "lc.roundResult": (p) => `Round ${p.round} result`,
  "lc.theCurrentAnswer": "the current answer",
  "lc.seeRanking": "See ranking",
  "lc.keepOrReplace": "Do you agree with this?",
  "lc.keepIt": "Yes",
  "lc.keeping": "Locking in…",
  "lc.replaceIt": "No",
  "lc.cnote": "Yes locks it in for the group · No lets you put a new idea to the vote.",
  "lc.replaceTag": (p) => `Round ${p.round} · your idea`,
  "lc.replacing": "The current winner",
  "lc.yourAlt": "What would you put instead?",
  "lc.altPlaceholder": "Your idea…",
  "lc.submitAlt": "Submit my idea",
  "lc.submitting": "Submitting…",
  "lc.anonNote": "Submitted anonymously · revealed once you've added yours.",
  "lc.keepInstead": "← Actually, keep it",
  "lc.errDuplicate": "That idea's already in.",
  "lc.errSubmit": "Couldn't submit your challenger. Try again.",
  "lc.currentBeingReplaced": "Current answer · being replaced",
  "lc.currentKeeping": "Current answer · you're keeping it",
  "lc.yourAltInHost": "✓ Your alternative is in — start voting when ready",
  "lc.yourAltInGuest": "✓ Your alternative is in — waiting for the host to start voting",
  "lc.altsThisRound": (p) => `Alternatives this round · ${p.n} so far`,
  "lc.noAltsYet": "No alternatives yet.",
  "lc.you": " · YOU",
  "lc.keptCount": (p) => `+ ${p.n} kept the current answer`,
  "lc.noAltsNote": "No alternatives — starting the vote locks in the answer.",
  "lc.altsNote": "Alternatives go up against the current answer when voting starts.",
  "lc.working": "Working…",
  "lc.startVoting": "Start voting",
  "lc.lockNote": (p) => `${p.n} responses · no alternatives — locks in the answer`,
  "lc.readyNote": (p) => `${p.n} responses · start voting when ready`,
  "lc.needNote": (p) => `${p.n} of ${p.need} responses · need ${p.need} to start voting`,
  "lc.waitHost": "Voting starts when the host's ready",
  "lc.errRecord": "Couldn't record that. Try again.",
  "lc.errAdvance": "Couldn't advance. Try again.",

  // ── Results ──
  "res.tallying": "Tallying…",
  "res.errLoad": "Couldn't load results.",
  "res.decided": "decided",
  "res.converged": (p) =>
    `Converged · ${p.ppl} ${plural(Number(p.ppl), "person", "people")} · ${p.cmp} ${plural(Number(p.cmp), "comparison", "comparisons")}`,
  "res.lockedIn": "The group locked it in",
  "res.keptByGroup": "Kept by the group",
  "res.noAlternatives": "no alternatives",
  "res.wonConsecutive": "Won consecutive rounds",
  "res.unbeaten": "Unbeaten",
  "res.people": (p) => `${p.ppl} ${plural(Number(p.ppl), "person", "people")}`,
  "res.fullRanking": "Full ranking",
  "res.noneRanked": "No ideas were ranked.",
  "res.howConverged": (p) => `How it converged · ${p.n} rounds`,
  "res.startAnother": "Start another decision",
  "res.playAgain": "Play again",
  // Game mode is instant (one round, confirmation_rounds_required=1): the result
  // is a reveal, not a convergence. These replace res.converged / res.lockedIn /
  // res.decided so the copy stays honest for a single-round game.
  "game.resultEyebrow": (p) =>
    `Winner · ${p.ppl} ${plural(Number(p.ppl), "player", "players")} · ${p.cmp} ${plural(Number(p.cmp), "comparison", "comparisons")}`,
  "game.pickLabel": "The group's pick",
  "game.votedPill": "voted",
  "game.namePrompt": "What should we call you?",
  "game.namePlaceholder": "Your name",
  "game.nameCta": "Join the game",
  "game.leaderboard": "Leaderboard",
  "game.you": "You",
  "game.by": (p) => `by ${p.name}`,
  "game.newQuestionPrompt": "Ask the group something new",
  "game.startNextGame": "Start the next game",
  "game.nextGame": "Next game",
  "game.nextGameNote": "The group picks the next topic together, then plays it.",
  "game.topicPrompt": "What's the next question?",
  "game.createEyebrow": "New game",
  "game.createQ": "What's the question?",
  "game.createHelp": "Everyone drops an idea, you vote head-to-head, and the best one wins.",
  "game.createPlaceholder": "e.g. Best pizza topping?",
  "game.createCta": "Start the game",
  "game.whosHere": "Who's here",
  "game.host": "host",
  "game.noStandings": "No standings yet — finish a game first.",
  "common.close": "Close",

  // ── History ──
  "hist.title": "How it converged",
  "hist.result": "Result",
  "hist.rounds": "rounds",
  "hist.errLoad": "Couldn't load history.",
  "hist.round": (p) => `Round ${p.n}`,
  "hist.wonAgain": "Won again",
  "hist.won": "Won",
  "hist.voted": (p) => `${p.n} voted`,
  "hist.keptIt": (p) => `${p.n} kept it`,
  "hist.dash": "—",
  "hist.seeRanking": "See ranking",
  "hist.convergedNote": "Converged — won consecutive rounds, locked in.",

  // ── RoundRanking ──
  "rr.voter": "voter",
  "rr.voters": "voters",
  "rr.rankingChip": (p) =>
    `Round ${p.n} ranking · ${p.locked ? "locked in" : "not locked yet"}`,
  "rr.errLoad": "Couldn't load ranking.",
  "rr.decidedBy": (p) =>
    `Decided by ${p.n} ${plural(Number(p.n), "voter", "voters")} this round`,
  "rr.lockedIn": "Locked in",
  "rr.leadsSoFar": "Leads so far",
  "rr.nothingRanked": "Nothing was ranked this round.",

  // ── InviteBlock ──
  "inv.title": "Invite your group",
  "inv.copied": "Copied",
  "inv.share": "Share",

  // ── RailInvite (dialog) ──
  "rail.invite": "Invite",
  "rail.dialogTitle": "Invite your group",
  "rail.dialogSub": "Send this link to your group, or have people in the room scan the code. They rank the options and you'll see the winner here — no account needed.",
  "rail.shareLink": "Share link",
  "rail.shareText": "Join my game on OneMind 🎮",
  "rail.copy": "Copy",
  "rail.copied": "Copied",
  "rail.orScan": "or scan to join",
  "rail.done": "Done",

  // ── PresenceBadge ──
  "pres.justYou": "just you",
  "pres.here": "here",

  // ── GlobalChat room (the continuous /c/GLOBAL room) ──
  "room.global": "Global",
  "room.here": "here",
  "room.invite": "Invite",
  // Telegram follow nudge (bold @onemind_life sits between pre/post).
  "room.followPre": "🔔 Follow ",
  "room.followPost": " for the daily winner",
  "room.followGo": "Follow",
  "room.dismiss": "Dismiss",
  // Record + live feed
  "room.recordEmpty": "Winning messages land here — the room’s permanent record.",
  "room.liveFeed": "Live feed · this round",
  "room.noMessages": "No messages yet — be the first.",
  "room.you": "you",
  // Proposing dock
  "room.proposingPhase": (p) => `Proposing · ${p.label} phase`,
  "room.takesGoal": (p) => `${p.n} in · need ${p.min} to vote`,
  "room.votingOpensInPre": "Voting opens in ",
  // Voting dock
  "room.votingLabel": "Voting",
  "room.votingStalledPre": "Waiting on the room · ",
  "room.votingStalledStrong": "your vote moves it on",
  "room.roundEndsInPre": "Round ends in ",
  // Between rounds
  "room.betweenPre": "The room is between rounds · ",
  "room.betweenStrong": "a new take opens shortly",
  // Celebration toast
  "room.celebrateWonBig": "✦ You won the room",
  "room.celebrateWonSub": "share it before the next round",
  // Arrival coach (mission) — centred overlay
  "room.coachPre": "The goal of OneMind is to ",
  "room.coachStrong": "unite the world",
  // Composer
  "room.ph0": "What's on your mind?",
  "room.ph1": "Say something to the world…",
  "room.ph2": "Add your take…",
  "room.ph3": "Say what you actually think…",
  "room.ph4": "The whole world's in here — say something…",
  "room.errDuplicate": "Someone already dropped that take.",
  "room.errPost": "Couldn’t post that — try again.",
  "room.send": "Send",
  "room.useThis": "use this",
  "room.dockHint": "The room votes the best line to the top",
  // Voting stage
  "room.voteDone": "Your vote’s in",
  "room.voteNarrowing": "Narrowing to one",
  "room.votersCount": (p) => `${p.n} voted`,
  "room.matchesCount": (p) => `${p.done} of ${p.total} matches`,
  "room.backThis": "Back this",
  "room.tooClose": "Too close",
  "room.skip": "Skip",
  "room.countingRoom": "Counting the room… the winner locks in when the clock runs out",
  "room.nothingTitle": "Nothing to vote on yet.",
  "room.nothingBody":
    "Invite a few more minds — the room needs at least two takes to narrow.",
  "room.loadingDuel": "Loading the duel…",
  "room.provisional": "Provisional · the room decides when the clock runs out",
  // Invite sheet
  "room.inviteTitle": "Pull someone into the room",
  "room.inviteSub":
    "The room only gets louder with more minds. Send the link or have someone scan — no account needed.",
  "room.share": "Share",
  "room.copied": "Copied",
  "room.copy": "Copy",
  "room.done": "Done",
  "room.inviteShareMsg": "Come settle something in the room 👇",
  // Winner share sheet (currently unreachable — no entry point wired)
  "room.shareWonTitle": "You won the room",
  "room.shareDecidedTitle": "The room decided",
  "room.shareMetaBeat": "beat",
  "room.shareMetaVoters": "voters",
  "room.shareMetaStand": "where do you stand?",
  "room.shareSub": "Share it — every take you send pulls in the next voice.",
  "room.shareCopied": "Copied to clipboard",
  "room.shareBtn": "Share this result",
  "room.shareTgMsg": (p) => `The room decided: “${p.text}” — where do you stand?`,
  "room.shareMessage": (p) =>
    `The room decided:\n“${p.text}”\n\nBeat ${p.beat} other ${plural(Number(p.beat), "take", "takes")} · ${p.voters} voters. Where do you stand?\n${p.url}`,
  // RoomClosed (scheduled room outside its window)
  "room.closedTitle": "The room is closed.",
  "room.untilOpens": "until it opens",
  "room.everyDayAt": (p) => `Every day at ${p.time}`,
  "room.yourTime": (p) => `${p.time} your time`,
  "room.openFor": (p) => `Open for ${p.len}`,
  "room.lenMinutes": (p) => `${p.n} minutes`,
  "room.notifyDoneTg": "See you there — the channel calls when it opens.",
  "room.notifyDoneWeb": "You'll get a ping when it opens.",
  "room.notifyMe": "Notify me when it opens",
  "room.lastWinningTake": "Last winning take",
  "room.now": "now",
  // Winner-card relative time (composed from winnerTimeParts + the viewer locale)
  "room.timeNow": "Just now",
  "room.timeMinsAgo": (p) => `${p.n}m ago`,
  "room.timeToday": (p) => `Today, ${p.time}`,
  "room.timeYesterday": (p) => `Yesterday, ${p.time}`,
  "room.timeDated": (p) => `${p.date}, ${p.time}`,
};

const ES: Dict = {
  // ── shared chrome ──
  "common.back": "Atrás",
  "common.loading": "Cargando…",
  "common.host": "Eres el anfitrión",
  "common.somethingWrong": "Algo salió mal",
  "common.tryAgain": "Algo salió mal. Inténtalo de nuevo.",

  // ── create ──
  "create.eyebrow": "Nueva decisión",
  "create.q": "¿Qué están decidiendo?",
  "create.help": "Tu grupo aportará ideas y luego las clasificará para encontrar la mejor.",
  "create.placeholder": "ej. ¿Dónde hacemos la reunión del equipo?",
  "create.cta": "Crear una sala para compartir",
  "create.creating": "Creando…",
  "create.consentPre": "Al crear una sala, aceptas nuestros ",
  "create.terms": "Términos",
  "create.consentAmp": " y ",
  "create.privacy": "Política de Privacidad",

  // ── ChatClient ──
  "chat.waitingHost": "Esperando a que el anfitrión empiece…",
  "chat.notFoundTitle": "Chat no encontrado",
  "chat.notFoundBody": "Este enlace no es válido o el chat ya no está disponible.",
  "chat.startYourOwn": "Crea tu propia decisión",
  "chat.approvalTitle": "Solicitud para unirse",
  "chat.approvalBody": "Este chat necesita la aprobación del anfitrión. (Próximamente.)",
  "chat.errCouldntLoad": "No se pudo cargar este chat.",
  "chat.errCouldntStart": "No se pudo iniciar el chat.",
  "chat.newRoom": "Sala nueva · ahora mismo",

  // ── SeedDialog ──
  "seed.title": "¿Cómo se aportan las ideas?",
  "seed.sub": "Cada quien aporta una idea y luego el grupo las clasifica — ahí es donde OneMind brilla.",
  "seed.fromGroup": "Recoger ideas del grupo",
  "seed.starting": "Empezando…",
  "seed.ai": "✦ Que la IA sugiera las opciones",
  "seed.aiThinking": "Pensando…",
  "seed.manual": "Yo añado las opciones",
  "seed.reviewTitle": "Revisa las opciones",
  "seed.typeTitle": "Escribe las opciones a clasificar",
  "seed.reviewSub": "La IA sugirió estas — edítalas o añade otras, luego el grupo las clasifica y confirma la ganadora.",
  "seed.typeSub": "La votación empieza en cuanto termines — el grupo las clasifica y confirma la ganadora.",
  "seed.option": (p) => `Opción ${p.n}`,
  "seed.addOption": "+ Añadir opción",
  "seed.getIdeasInstead": "Mejor recoger ideas",
  "seed.startVoting": "Empezar votación",

  // ── Proposing ──
  "prop.tagHost": "Proponiendo · añade una idea",
  "prop.tagGuest": "Proponiendo · añade tu idea",
  "prop.yourIdeaIn": "✓ Tu idea está registrada",
  "prop.placeholder": "Escribe tu idea — una opción clara…",
  "prop.addIdea": "Añadir idea",
  "prop.adding": "Añadiendo…",
  "prop.errDuplicate": "Alguien ya añadió esa idea.",
  "prop.errAdd": "No se pudo añadir tu idea. Inténtalo de nuevo.",
  "prop.errStartVoting": "No se pudo empezar la votación. Inténtalo de nuevo.",
  "prop.responses": (p) =>
    `${p.n} ${plural(Number(p.n), "respuesta", "respuestas")} de tu grupo`,
  "prop.revealed": "Revelado",
  "prop.hidden": "Oculto",
  "prop.revealedNote": "Reveladas porque añadiste la tuya — estas se clasifican a continuación.",
  "prop.hiddenNote": "Añade tu propia idea para revelar las demás.",
  "prop.you": " · tú",
  "prop.waitHost": "La votación empieza cuando el anfitrión esté listo",
  "prop.startVoting": "Empezar votación",
  "prop.starting": "Empezando…",
  "prop.readyNote": (p) =>
    `${p.n} ${plural(Number(p.n), "respuesta", "respuestas")} · empieza la votación cuando quieras`,
  "prop.needNote": (p) =>
    `${p.n} de ${p.need} respuestas · faltan ${p.need} para empezar a votar`,

  // ── Voting ──
  "vote.prompt": (p) => `Ronda ${p.round} · ¿cuál es mejor? Toca una.`,
  "vote.currentAnswer": "Respuesta actual",
  "vote.alternative": "Alternativa",
  "vote.keepIt": "Mantenerla",
  "vote.pick": "Elegir",
  "vote.recording": "Registrando…",
  "vote.equal": "Igual",
  "vote.skipPair": "Saltar este par",
  "vote.skipping": "Saltando…",
  "vote.nothingTitle": "Aún no hay nada que votar",
  "vote.nothingBody": "Para que sea justo, no votas por tu propia idea — y todavía no hay suficientes ideas de otros para comparar. ",
  "vote.nothingHost": "Invita a más personas para que el grupo pueda votar.",
  "vote.nothingGuest": "Espera un momento mientras se unen más personas.",
  "vote.doneTitle": "Tus votos están registrados.",
  "vote.doneHost": "Todos votan los mismos pares. Termina la votación cuando suficientes personas hayan acabado.",
  "vote.doneGuest": "Todos votan los mismos pares. La ronda termina cuando el anfitrión cierra la votación.",
  "vote.tallying": "Contando…",
  "vote.endNow": "Terminar votación",
  "vote.noVotesYet": "Aún no hay votos — invita a alguien que pueda votar",
  "vote.doneCountReady": (p) => `${p.n} terminaron de votar · termina cuando quieras`,
  "vote.doneCountNeed": (p) =>
    `${p.n} de ${p.need} terminaron · faltan ${p.need} para terminar`,
  "vote.waitHostEnds": "La ronda termina cuando el anfitrión cierra la votación",
  "vote.errVote": "No se pudo registrar tu voto.",
  "vote.errEnd": "No se pudo terminar la votación. Inténtalo de nuevo.",
  "vote.errSkip": "No se pudo saltar. Inténtalo de nuevo.",
  "vote.errLoad": "No se pudo cargar la votación.",

  // ── LeaderChallenge ──
  "lc.roundResult": (p) => `Resultado de la ronda ${p.round}`,
  "lc.theCurrentAnswer": "la respuesta actual",
  "lc.seeRanking": "Ver clasificación",
  "lc.keepOrReplace": "¿Estás de acuerdo con esto?",
  "lc.keepIt": "Sí",
  "lc.keeping": "Fijando…",
  "lc.replaceIt": "No",
  "lc.cnote": "Sí la fija para el grupo · No te deja someter una idea nueva a votación.",
  "lc.replaceTag": (p) => `Ronda ${p.round} · tu idea`,
  "lc.replacing": "El ganador actual",
  "lc.yourAlt": "¿Qué pondrías en su lugar?",
  "lc.altPlaceholder": "Tu idea…",
  "lc.submitAlt": "Enviar mi idea",
  "lc.submitting": "Enviando…",
  "lc.anonNote": "Enviada de forma anónima · se revela cuando añadas la tuya.",
  "lc.keepInstead": "← Mejor déjalo así",
  "lc.errDuplicate": "Esa idea ya está.",
  "lc.errSubmit": "No se pudo enviar tu alternativa. Inténtalo de nuevo.",
  "lc.currentBeingReplaced": "Respuesta actual · siendo reemplazada",
  "lc.currentKeeping": "Respuesta actual · la estás manteniendo",
  "lc.yourAltInHost": "✓ Tu alternativa está registrada — empieza la votación cuando quieras",
  "lc.yourAltInGuest": "✓ Tu alternativa está registrada — esperando a que el anfitrión empiece la votación",
  "lc.altsThisRound": (p) => `Alternativas esta ronda · ${p.n} hasta ahora`,
  "lc.noAltsYet": "Aún no hay alternativas.",
  "lc.you": " · TÚ",
  "lc.keptCount": (p) => `+ ${p.n} mantuvieron la respuesta actual`,
  "lc.noAltsNote": "Sin alternativas — empezar la votación fija la respuesta.",
  "lc.altsNote": "Las alternativas compiten contra la respuesta actual cuando empieza la votación.",
  "lc.working": "Procesando…",
  "lc.startVoting": "Empezar votación",
  "lc.lockNote": (p) => `${p.n} respuestas · sin alternativas — fija la respuesta`,
  "lc.readyNote": (p) => `${p.n} respuestas · empieza la votación cuando quieras`,
  "lc.needNote": (p) => `${p.n} de ${p.need} respuestas · faltan ${p.need} para empezar a votar`,
  "lc.waitHost": "La votación empieza cuando el anfitrión esté listo",
  "lc.errRecord": "No se pudo registrar. Inténtalo de nuevo.",
  "lc.errAdvance": "No se pudo avanzar. Inténtalo de nuevo.",

  // ── Results ──
  "res.tallying": "Contando…",
  "res.errLoad": "No se pudieron cargar los resultados.",
  "res.decided": "decidieron",
  "res.converged": (p) =>
    `Convergió · ${p.ppl} ${plural(Number(p.ppl), "persona", "personas")} · ${p.cmp} ${plural(Number(p.cmp), "comparación", "comparaciones")}`,
  "res.lockedIn": "El grupo la fijó",
  "res.keptByGroup": "Mantenida por el grupo",
  "res.noAlternatives": "sin alternativas",
  "res.wonConsecutive": "Ganó rondas consecutivas",
  "res.unbeaten": "Invicta",
  "res.people": (p) => `${p.ppl} ${plural(Number(p.ppl), "persona", "personas")}`,
  "res.fullRanking": "Clasificación completa",
  "res.noneRanked": "No se clasificó ninguna idea.",
  "res.howConverged": (p) => `Cómo convergió · ${p.n} rondas`,
  "res.startAnother": "Empezar otra decisión",
  "res.playAgain": "Jugar otra vez",
  // Juego = instantáneo (una ronda): el resultado es una revelación, no una
  // convergencia. Reemplazan res.converged / res.lockedIn / res.decided.
  "game.resultEyebrow": (p) =>
    `Ganadora · ${p.ppl} ${plural(Number(p.ppl), "jugador", "jugadores")} · ${p.cmp} ${plural(Number(p.cmp), "comparación", "comparaciones")}`,
  "game.pickLabel": "La elección del grupo",
  "game.votedPill": "votaron",
  "game.namePrompt": "¿Cómo te llamamos?",
  "game.namePlaceholder": "Tu nombre",
  "game.nameCta": "Entrar al juego",
  "game.leaderboard": "Posiciones",
  "game.you": "Tú",
  "game.by": (p) => `de ${p.name}`,
  "game.newQuestionPrompt": "Pregúntale algo nuevo al grupo",
  "game.startNextGame": "Empezar el siguiente juego",
  "game.nextGame": "Siguiente juego",
  "game.nextGameNote": "El grupo elige el próximo tema en conjunto y luego lo juega.",
  "game.topicPrompt": "¿Cuál es la siguiente pregunta?",
  "game.createEyebrow": "Nuevo juego",
  "game.createQ": "¿Cuál es la pregunta?",
  "game.createHelp": "Cada quien propone una idea, votan mano a mano y gana la mejor.",
  "game.createPlaceholder": "ej. ¿Mejor ingrediente para pizza?",
  "game.createCta": "Iniciar el juego",
  "game.whosHere": "Quién está",
  "game.host": "anfitrión",
  "game.noStandings": "Aún no hay posiciones — termina un juego primero.",
  "common.close": "Cerrar",

  // ── History ──
  "hist.title": "Cómo convergió",
  "hist.result": "Resultado",
  "hist.rounds": "rondas",
  "hist.errLoad": "No se pudo cargar el historial.",
  "hist.round": (p) => `Ronda ${p.n}`,
  "hist.wonAgain": "Ganó otra vez",
  "hist.won": "Ganó",
  "hist.voted": (p) => `${p.n} votaron`,
  "hist.keptIt": (p) => `${p.n} la mantuvieron`,
  "hist.dash": "—",
  "hist.seeRanking": "Ver clasificación",
  "hist.convergedNote": "Convergió — ganó rondas consecutivas, fijada.",

  // ── RoundRanking ──
  "rr.voter": "votante",
  "rr.voters": "votantes",
  "rr.rankingChip": (p) =>
    `Clasificación de la ronda ${p.n} · ${p.locked ? "fijada" : "aún no fijada"}`,
  "rr.errLoad": "No se pudo cargar la clasificación.",
  "rr.decidedBy": (p) =>
    `Decidida por ${p.n} ${plural(Number(p.n), "votante", "votantes")} esta ronda`,
  "rr.lockedIn": "Fijada",
  "rr.leadsSoFar": "Lidera por ahora",
  "rr.nothingRanked": "No se clasificó nada esta ronda.",

  // ── InviteBlock ──
  "inv.title": "Invita a tu grupo",
  "inv.copied": "Copiado",
  "inv.share": "Compartir",

  // ── RailInvite (dialog) ──
  "rail.invite": "Invitar",
  "rail.dialogTitle": "Invita a tu grupo",
  "rail.dialogSub": "Envía este enlace a tu grupo, o deja que las personas en la sala escaneen el código. Ellos clasifican las opciones y verás la ganadora aquí — sin necesidad de cuenta.",
  "rail.shareLink": "Compartir enlace",
  "rail.shareText": "Únete a mi juego en OneMind 🎮",
  "rail.copy": "Copiar",
  "rail.copied": "Copiado",
  "rail.orScan": "o escanea para unirte",
  "rail.done": "Listo",

  // ── PresenceBadge ──
  "pres.justYou": "solo tú",
  "pres.here": "aquí",

  // ── GlobalChat room (la sala continua /c/GLOBAL) ──
  "room.global": "Global",
  "room.here": "aquí",
  "room.invite": "Invitar",
  "room.followPre": "🔔 Sigue ",
  "room.followPost": " para ver la ganadora del día",
  "room.followGo": "Seguir",
  "room.dismiss": "Descartar",
  "room.recordEmpty": "Los mensajes ganadores aparecen aquí — el registro permanente de la sala.",
  "room.liveFeed": "En vivo · esta ronda",
  "room.noMessages": "Aún no hay mensajes — sé el primero.",
  "room.you": "tú",
  "room.proposingPhase": (p) => `Proponiendo · ${p.label}`,
  // "se necesitan {min}" = total framing (matches EN "need {min}"), so it's
  // correct at n=1; "listas" agrees with "ideas" (feminine), pluralized.
  "room.takesGoal": (p) =>
    `${p.n} ${plural(Number(p.n), "lista", "listas")} · se necesitan ${p.min} para votar`,
  "room.votingOpensInPre": "La votación abre en ",
  "room.votingLabel": "Votación",
  "room.votingStalledPre": "Esperando a la sala · ",
  "room.votingStalledStrong": "tu voto la hace avanzar",
  "room.roundEndsInPre": "La ronda termina en ",
  "room.betweenPre": "La sala está entre rondas · ",
  "room.betweenStrong": "pronto se abre un nuevo turno",
  "room.celebrateWonBig": "✦ Ganaste la sala",
  "room.celebrateWonSub": "compártelo antes de la próxima ronda",
  "room.coachPre": "El objetivo de OneMind es ",
  "room.coachStrong": "unir al mundo",
  "room.ph0": "¿Qué estás pensando?",
  "room.ph1": "Dile algo al mundo…",
  "room.ph2": "Comparte tu opinión…",
  "room.ph3": "Di lo que de verdad piensas…",
  "room.ph4": "El mundo entero está aquí — di algo…",
  "room.errDuplicate": "Alguien ya publicó esa idea.",
  "room.errPost": "No se pudo publicar — inténtalo de nuevo.",
  "room.send": "Enviar",
  "room.useThis": "usa esta",
  "room.dockHint": "La sala vota la mejor línea hasta arriba",
  "room.voteDone": "Tu voto está listo",
  "room.voteNarrowing": "Reduciendo a una",
  "room.votersCount": (p) => `${p.n} ${plural(Number(p.n), "votó", "votaron")}`,
  "room.matchesCount": (p) => `${p.done} de ${p.total} comparaciones`,
  "room.backThis": "Elige esta",
  "room.tooClose": "Muy parejo",
  "room.skip": "Saltar",
  "room.countingRoom": "Contando la sala… la ganadora se fija cuando termine el reloj",
  "room.nothingTitle": "Aún no hay nada que votar.",
  "room.nothingBody":
    "Invita a más mentes — la sala necesita al menos dos ideas para reducir.",
  "room.loadingDuel": "Cargando el duelo…",
  "room.provisional": "Provisional · la sala decide cuando termina el reloj",
  "room.inviteTitle": "Trae a alguien a la sala",
  "room.inviteSub":
    "La sala se anima con más mentes. Envía el enlace o deja que alguien escanee — sin necesidad de cuenta.",
  "room.share": "Compartir",
  "room.copied": "Copiado",
  "room.copy": "Copiar",
  "room.done": "Listo",
  "room.inviteShareMsg": "Ven a resolver algo en la sala 👇",
  "room.shareWonTitle": "Ganaste la sala",
  "room.shareDecidedTitle": "La sala decidió",
  "room.shareMetaBeat": "venció a",
  "room.shareMetaVoters": "votantes",
  "room.shareMetaStand": "¿tú qué opinas?",
  "room.shareSub": "Compártelo — cada idea que envías trae la siguiente voz.",
  "room.shareCopied": "Copiado al portapapeles",
  "room.shareBtn": "Compartir este resultado",
  "room.shareTgMsg": (p) => `La sala decidió: “${p.text}” — ¿tú qué opinas?`,
  "room.shareMessage": (p) =>
    `La sala decidió:\n“${p.text}”\n\nVenció a ${p.beat} ${plural(Number(p.beat), "idea", "ideas")} · ${p.voters} votantes. ¿Tú qué opinas?\n${p.url}`,
  "room.closedTitle": "La sala está cerrada.",
  "room.untilOpens": "hasta que abra",
  "room.everyDayAt": (p) => `Todos los días a las ${p.time}`,
  "room.yourTime": (p) => `${p.time} tu hora`,
  "room.openFor": (p) => `Abierta por ${p.len}`,
  "room.lenMinutes": (p) => `${p.n} minutos`,
  "room.notifyDoneTg": "Nos vemos ahí — el canal te avisa cuando abra.",
  "room.notifyDoneWeb": "Te avisaremos cuando abra.",
  "room.notifyMe": "Avísame cuando abra",
  "room.lastWinningTake": "Última idea ganadora",
  "room.now": "ahora",
  "room.timeNow": "Justo ahora",
  "room.timeMinsAgo": (p) => `hace ${p.n}m`,
  "room.timeToday": (p) => `Hoy, ${p.time}`,
  "room.timeYesterday": (p) => `Ayer, ${p.time}`,
  "room.timeDated": (p) => `${p.date}, ${p.time}`,
};

const DICTS: Record<Lang, Dict> = { en: EN, es: ES };

/// The language a TRANSLATION-ENABLED surface should open in: an explicit
/// persisted choice wins; otherwise the device language (es* → Spanish);
/// otherwise English. Deliberately NOT applied app-wide — the provider stays
/// English everywhere, and only the translated room opts in via setLang(
/// preferredLang()), so a Spanish device does not auto-translate GLOBAL or the
/// rest of the app. Guarded so a private-mode/SSR call can't throw.
export function preferredLang(): Lang {
  if (typeof window === "undefined") return "en";
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === "en" || stored === "es") return stored;
  } catch {
    /* localStorage blocked — fall through to the device language */
  }
  try {
    const nav = window.navigator;
    const candidates = [nav?.language, nav?.languages?.[0]];
    for (const c of candidates) {
      if (typeof c === "string" && c.toLowerCase().startsWith("es")) return "es";
    }
  } catch {
    /* navigator unavailable — default to English */
  }
  return "en";
}

type I18n = {
  lang: Lang;
  setLang: (l: Lang) => void;
  t: (key: string, params?: Params) => string;
};

const I18nContext = createContext<I18n | null>(null);

export function LangProvider({ children }: { children: ReactNode }) {
  // Start at 'en' so the server-rendered HTML and the first client render
  // match (no hydration mismatch). The real language is resolved in the effect
  // below, then the tree re-renders. Persisted via localStorage.
  const [lang, setLangState] = useState<Lang>("en");

  useEffect(() => {
    // App-wide default is English — the provider does NOT auto-apply the device
    // language. Only a translation-enabled surface opts in (it calls
    // setLang(preferredLang()) on mount), so a Spanish device leaves GLOBAL and
    // the rest of the app in English until the user is actually in a translated
    // chat. Keeps SSR HTML and first client render both 'en' (no hydration
    // mismatch).
    document.documentElement.lang = "en";
  }, []);

  const setLang = useCallback((l: Lang) => {
    setLangState(l);
    try {
      window.localStorage.setItem(STORAGE_KEY, l);
    } catch {
      /* ignore */
    }
    document.documentElement.lang = l;
  }, []);

  const t = useCallback(
    (key: string, params?: Params) => {
      const entry = DICTS[lang][key] ?? EN[key];
      if (entry == null) return key;
      return typeof entry === "function" ? entry(params ?? {}) : entry;
    },
    [lang],
  );

  const value = useMemo<I18n>(() => ({ lang, setLang, t }), [lang, setLang, t]);
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18n {
  const ctx = useContext(I18nContext);
  if (!ctx) {
    // Defensive fallback (e.g. a component rendered outside the provider during
    // a static prerender): English, no persistence.
    return {
      lang: "en",
      setLang: () => {},
      t: (key, params) => {
        const entry = EN[key];
        if (entry == null) return key;
        return typeof entry === "function" ? entry(params ?? {}) : entry;
      },
    };
  }
  return ctx;
}
