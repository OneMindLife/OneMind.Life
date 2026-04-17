// FCM v1 API helper for sending push notifications
// Requires FCM_SERVICE_ACCOUNT_JSON secret set in Supabase

import { createClient } from "jsr:@supabase/supabase-js@2";

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

/** Send a data-only push notification to multiple FCM tokens. */
export async function sendPushToTokens(
  tokens: string[],
  data: { title: string; body: string; chat_id: string }
): Promise<void> {
  if (!FCM_SERVICE_ACCOUNT_JSON || tokens.length === 0) return;

  const sa: ServiceAccount = JSON.parse(FCM_SERVICE_ACCOUNT_JSON);
  const accessToken = await getAccessToken(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  const results = await Promise.allSettled(
    tokens.map((token) =>
      fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            data: {
              title: data.title,
              body: data.body,
              chat_id: data.chat_id,
            },
          },
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
    console.warn(`[FCM] ${failCount}/${tokens.length} notifications failed`);
  }
}

/** Query participant FCM tokens for a chat and send a phase-change notification. */
export async function notifyPhaseChange(
  supabase: ReturnType<typeof createClient>,
  chatId: number,
  chatName: string,
  newPhase: string
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

    // Get FCM tokens for those users
    const { data: fcmTokens, error: fcmError } = await supabase
      .from("fcm_tokens")
      .select("token")
      .in("user_id", userIds);

    if (fcmError) {
      console.error(`[FCM] Error fetching tokens for chat ${chatId}: ${fcmError.message}`);
      return;
    }
    if (!fcmTokens || fcmTokens.length === 0) {
      console.log(`[FCM] No FCM tokens for chat ${chatId} (${participants.length} participants, 0 tokens)`);
      return;
    }

    const tokens = fcmTokens.map((t: any) => t.token);
    const phaseLabel =
      newPhase === "rating" ? "Rating" : newPhase === "proposing" ? "Proposing" : newPhase;

    console.log(`[FCM] Sending ${tokens.length} notifications for chat ${chatId} (${chatName}) → ${newPhase}`);

    await sendPushToTokens(tokens, {
      title: chatName,
      body: `${phaseLabel} phase has started`,
      chat_id: String(chatId),
    });

    console.log(`[FCM] Done: ${tokens.length} notifications sent for chat ${chatId}`);
  } catch (err) {
    // Never fail phase transitions because of notification errors
    console.error(`[FCM] Error sending notifications for chat ${chatId}: ${err.message}`);
  }
}
