// Ad-hoc test-push sender: sends a data-only FCM notification to a user's
// registered tokens (or all tokens) and returns the per-token FCM API result.
// Used to verify the push pipeline end-to-end. Requires FCM_SERVICE_ACCOUNT_JSON.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SA_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\s/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
function base64url(data: ArrayBuffer | string): string {
  const str = typeof data === "string" ? btoa(data) : btoa(String.fromCharCode(...new Uint8Array(data)));
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey("pkcs8", pemToArrayBuffer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${base64url(sig)}`;
  const resp = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}` });
  const r = await resp.json();
  if (!r.access_token) throw new Error("auth failed: " + JSON.stringify(r));
  return r.access_token;
}

Deno.serve(async (req) => {
  try {
    if (!SA_JSON) return new Response(JSON.stringify({ error: "FCM_SERVICE_ACCOUNT_JSON not set" }), { status: 500 });
    const sa = JSON.parse(SA_JSON);
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const body = await req.json().catch(() => ({}));
    const userId = body.user_id;
    const title = body.title ?? "OneMind";
    const msg = body.body ?? "Test notification — it works!";
    const chatId = String(body.chat_id ?? "1049");

    let q = supabase.from("fcm_tokens").select("token");
    if (userId) q = q.eq("user_id", userId);
    const { data: rows, error } = await q;
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    const tokens = (rows ?? []).map((r: any) => r.token);
    if (!tokens.length) return new Response(JSON.stringify({ sent: 0, note: "no tokens for that user" }), { status: 200 });

    const accessToken = await getAccessToken(sa);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const results = [];
    for (const token of tokens) {
      const resp = await fetch(url, { method: "POST", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ message: { token, data: { title, body: msg, chat_id: chatId } } }) });
      const text = await resp.text();
      results.push({ status: resp.status, body: text.slice(0, 300) });
    }
    return new Response(JSON.stringify({ attempted: tokens.length, results }, null, 2), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
