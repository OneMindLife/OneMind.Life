import { createClient } from "@supabase/supabase-js";

// Browser Supabase client for the wedge (anonymous auth model — same backend as
// the Flutter app, reused unchanged; see docs/wedge-spec/04-data-contracts.md).
// Static-export app: everything runs client-side, so a single browser client
// (session persisted in localStorage) is all we need. The anon key is a public
// publishable key (it ships in the client bundle by design; RLS does the gating).
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    "Missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY — copy .env.local.example to .env.local.",
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
  },
});

/// Ensure an anonymous session exists (lazy — call before any write that needs
/// auth.uid()). Mirrors the Flutter app's `ensureSignedIn`.
///
/// Concurrency-guarded: the chat screen fires ensureSignedIn from BOTH
/// ensureParticipant (auto-join) and usePresence on mount. Without the shared
/// in-flight promise, a transient null getSession() lets both call
/// signInAnonymously() → TWO anonymous users, one of which gets auto-joined as a
/// never-acting "phantom" participant (observed in ~11% of games, 2026-06-25).
/// Sharing one sign-in collapses concurrent callers onto a single anon user.
let inFlightSignIn:
  | Promise<Awaited<ReturnType<typeof supabase.auth.signInAnonymously>>>
  | null = null;

export async function ensureSignedIn() {
  const { data } = await supabase.auth.getSession();
  if (data.session) return data.session;
  if (!inFlightSignIn) {
    inFlightSignIn = supabase.auth.signInAnonymously();
    // Clear the slot once it settles so a later (genuinely new) session can sign in.
    inFlightSignIn.finally(() => {
      inFlightSignIn = null;
    });
  }
  const { data: signed, error } = await inFlightSignIn;
  if (error) throw error;
  return signed.session;
}
