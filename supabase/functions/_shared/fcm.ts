// FCM v1 API helper for sending push notifications
// Requires FCM_SERVICE_ACCOUNT_JSON secret set in Supabase


const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64url(data: ArrayBuffer | string): string {
  const str =
    typeof data === "string"
      ? btoa(data)
      : btoa(String.fromCharCode(...new Uint8Array(data)));
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );

  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput)
  );
  const jwt = `${signingInput}.${base64url(signature)}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const result = await resp.json();
  if (!result.access_token) {
    console.error("[FCM] Failed to get access token:", result);
    throw new Error("FCM auth failed");
  }
  return result.access_token;
}

export interface PushTarget {
  token: string;
  /** 'web' | 'android' | 'ios' — from fcm_tokens.platform */
  platform?: string;
}

/**
 * Build the platform-appropriate FCM v1 message for one token.
 *
 * Web tokens get a DATA-ONLY message: the service worker
 * (web/firebase-messaging-sw.js) renders it via onBackgroundMessage, and a
 * `notification` block would bypass the SW and double-display.
 *
 * Mobile tokens get a `notification` block so the OS renders it natively
 * when the app is backgrounded/terminated (data-only messages display
 * nothing on Android/iOS without a client background handler). The data
 * payload rides along for tap-routing (chat_id → open chat).
 */
export function buildMessageForTarget(
  target: PushTarget,
  data: { title: string; body: string; chat_id: string; code: string }
): Record<string, unknown> {
  const base = {
    token: target.token,
    data: {
      title: data.title,
      body: data.body,
      chat_id: data.chat_id,
      // Invite code so the wedge SW can route a tap to /g/<code>. FCM data
      // values must be strings; empty falls back to GLOBAL client-side.
      code: data.code,
    },
  };

  if (!target.platform || target.platform === "web") {
    return base;
  }

  return {
    ...base,
    notification: { title: data.title, body: data.body },
    android: { priority: "HIGH" },
    apns: { payload: { aps: { sound: "default" } } },
  };
}

/** Send a push notification to multiple FCM tokens (platform-aware). */
export async function sendPushToTokens(
  targets: PushTarget[],
  data: { title: string; body: string; chat_id: string; code: string }
): Promise<void> {
  if (!FCM_SERVICE_ACCOUNT_JSON || targets.length === 0) return;

  const sa: ServiceAccount = JSON.parse(FCM_SERVICE_ACCOUNT_JSON);
  const accessToken = await getAccessToken(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  const results = await Promise.allSettled(
    targets.map((target) =>
      fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: buildMessageForTarget(target, data),
        }),
      })
    )
  );

  let failCount = 0;
  for (let i = 0; i < results.length; i++) {
    if (results[i].status === "rejected") {
      failCount++;
      console.warn(`[FCM] Token ${i} failed: ${(results[i] as PromiseRejectedResult).reason}`);
    } else {
      const resp = (results[i] as PromiseFulfilledResult<Response>).value;
      if (!resp.ok) {
        failCount++;
        const body = await resp.text().catch(() => "");
        console.warn(`[FCM] Token ${i} HTTP ${resp.status}: ${body}`);
      }
    }
  }
  if (failCount > 0) {
    console.warn(`[FCM] ${failCount}/${targets.length} notifications failed`);
  }
}

/** Query participant FCM tokens for a chat and send a phase-change notification. */
export async function notifyPhaseChange(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  chatId: number,
  chatName: string,
  newPhase: string
): Promise<void> {
  const phaseLabel =
    newPhase === "rating" ? "Rating" : newPhase === "proposing" ? "Proposing" : newPhase;
  await notifyChatEvent(supabase, chatId, chatName, `${phaseLabel} phase has started`);
}

/** Query participant FCM tokens for a chat and send an arbitrary notification. */
export async function notifyChatEvent(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  chatId: number,
  title: string,
  body: string
): Promise<void> {
  if (!FCM_SERVICE_ACCOUNT_JSON) {
    console.warn(`[FCM] Skipped: FCM_SERVICE_ACCOUNT_JSON not set`);
    return;
  }

  try {
    // Get user_ids of active participants
    const { data: participants, error: partError } = await supabase
      .from("participants")
      .select("user_id")
      .eq("chat_id", chatId)
      .eq("status", "active")
      .not("user_id", "is", null);

    if (partError) {
      console.error(`[FCM] Error fetching participants for chat ${chatId}: ${partError.message}`);
      return;
    }
    if (!participants || participants.length === 0) {
      console.log(`[FCM] No participants for chat ${chatId}, skipping`);
      return;
    }

    const userIds = participants.map((p: any) => p.user_id);

    // Invite code for tap-routing (/g/<code> in the wedge SW). One cheap lookup.
    const { data: chatRow } = await supabase
      .from("chats")
      .select("invite_code")
      .eq("id", chatId)
      .maybeSingle();
    const code: string = chatRow?.invite_code ?? "";

    // Get FCM tokens (with platform, to shape the message) for those users
    const { data: fcmTokens, error: fcmError } = await supabase
      .from("fcm_tokens")
      .select("token, platform")
      .in("user_id", userIds);

    if (fcmError) {
      console.error(`[FCM] Error fetching tokens for chat ${chatId}: ${fcmError.message}`);
      return;
    }
    if (!fcmTokens || fcmTokens.length === 0) {
      console.log(`[FCM] No FCM tokens for chat ${chatId} (${participants.length} participants, 0 tokens)`);
      return;
    }

    const targets = fcmTokens.map((t: any) => ({
      token: t.token,
      platform: t.platform,
    }));

    console.log(`[FCM] Sending ${targets.length} notifications for chat ${chatId} (${title}) → ${body}`);

    await sendPushToTokens(targets, {
      title,
      body,
      chat_id: String(chatId),
      code,
    });

    console.log(`[FCM] Done: ${targets.length} notifications sent for chat ${chatId}`);
  } catch (err) {
    // Never fail phase transitions because of notification errors
    console.error(`[FCM] Error sending notifications for chat ${chatId}: ${(err as Error).message}`);
  }
}
