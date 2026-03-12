import http from "k6/http";
import { check, sleep } from "k6";
import { AUTH_URL, SUPABASE_ANON_KEY, TEST_PREFIX } from "../config/env.js";

// Expected statuses — 429 rate limits are expected under load, not errors
const AUTH_EXPECTED = { responseCallback: http.expectedStatuses(200, 429) };

// Per-VU token cache (module-level variables are VU-scoped in k6)
let _cachedAuth = null;

/**
 * Sign up as an anonymous user via Supabase Auth.
 * Retries up to 5 times with exponential backoff + jitter on 429 rate limits.
 * Returns { access_token, user_id } or null on failure.
 */
export function signupAnonymous() {
  let res;
  for (let attempt = 0; attempt < 5; attempt++) {
    res = http.post(
      `${AUTH_URL}/signup`,
      JSON.stringify({}),
      {
        headers: {
          "Content-Type": "application/json",
          apikey: SUPABASE_ANON_KEY,
        },
        tags: { name: "signup" },
        ...AUTH_EXPECTED,
      }
    );

    if (res.status !== 429) break;
    // Exponential backoff: 1-2s, 2-4s, 4-8s, 8-16s, 16-32s with jitter
    const backoff = Math.pow(2, attempt) * (1 + Math.random());
    sleep(backoff);
  }

  const ok = check(res, {
    "signup: status 200": (r) => r.status === 200,
    "signup: has access_token": (r) => {
      try { return !!JSON.parse(r.body).access_token; }
      catch { return false; }
    },
  });

  if (!ok) return null;

  const body = JSON.parse(res.body);
  return {
    access_token: body.access_token,
    user_id: body.user?.id || null,
  };
}

/**
 * Get or create an auth session for this VU.
 * Signs up once on the first iteration, then reuses the token.
 * Does NOT cache failures — retries on next call.
 */
export function getOrCreateAuth() {
  if (_cachedAuth) return _cachedAuth;
  const auth = signupAnonymous();
  if (auth) _cachedAuth = auth;
  return auth;
}

/**
 * Set display name for the authenticated user.
 * Retries up to 3 times with exponential backoff on 429 rate limits.
 */
export function setDisplayName(token, vuId) {
  const displayName = `${TEST_PREFIX}user_${vuId}_${Date.now()}`;

  let res;
  for (let attempt = 0; attempt < 3; attempt++) {
    res = http.put(
      `${AUTH_URL}/user`,
      JSON.stringify({
        data: { display_name: displayName },
      }),
      {
        headers: {
          "Content-Type": "application/json",
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${token}`,
        },
        tags: { name: "set_display_name" },
        ...AUTH_EXPECTED,
      }
    );

    if (res.status !== 429) break;
    sleep(Math.pow(2, attempt)); // 1s, 2s, 4s
  }

  check(res, {
    "set_name: status 200": (r) => r.status === 200,
  });

  return displayName;
}
