import { supabase, ensureSignedIn } from "@/lib/supabase/client";

// Web push for the wedge. The server half (notify_push_round trigger →
// push-events → FCM fan-out to fcm_tokens) is already live in prod; this module
// is the client half — it registers a token so the away user actually gets the
// "new round is open" ping.
//
// Firebase is loaded LAZILY from the gstatic CDN only when the user opts in, so
// it never touches the wedge's cold-start bundle (fast mobile load is the whole
// reason the wedge exists over Flutter). FCM project = YOUR_FIREBASE_PROJECT_ID, the same
// project whose service account the sender uses; independent of hosting.

const FIREBASE_CONFIG = {
  apiKey: "YOUR_FIREBASE_API_KEY",
  appId: "YOUR_FIREBASE_APP_ID",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  projectId: "YOUR_FIREBASE_PROJECT_ID",
  authDomain: "YOUR_FIREBASE_PROJECT_ID.firebaseapp.com",
  storageBucket: "YOUR_FIREBASE_PROJECT_ID.firebasestorage.app",
  measurementId: "G-2XCF0J8BGQ",
};

// Public VAPID key (reused verbatim from the Flutter app — same FCM project).
const VAPID_KEY =
  "BAIuf37ss69F23wPAa7z_pXwK3ym1GWaEZes45Nj847qH2Ry-Qqk86ifmOyN9A2kSQnQAjy-Oaw-n3IS76Nz92c";

const SW_URL = "/firebase-messaging-sw.js";
const CDN = "https://www.gstatic.com/firebasejs/10.12.0";

export type PushPermission = "default" | "granted" | "denied" | "unsupported";

/// True only where web push can actually work. Note iOS Safari exposes
/// PushManager ONLY inside an installed PWA (standalone) — a plain iOS Safari
/// tab returns false here, which is what we want (don't offer a dead button).
export function isPushSupported(): boolean {
  return (
    typeof window !== "undefined" &&
    "serviceWorker" in navigator &&
    "Notification" in window &&
    "PushManager" in window
  );
}

/// Current permission (without prompting). "unsupported" short-circuits the UI.
export function pushPermission(): PushPermission {
  if (!isPushSupported()) return "unsupported";
  return Notification.permission as PushPermission;
}

// --- lazy CDN loader (idempotent) ------------------------------------------

let firebaseLoad: Promise<void> | null = null;

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) {
      resolve();
      return;
    }
    const s = document.createElement("script");
    s.src = src;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(`failed to load ${src}`));
    document.head.appendChild(s);
  });
}

async function loadFirebase(): Promise<void> {
  if (!firebaseLoad) {
    firebaseLoad = (async () => {
      await loadScript(`${CDN}/firebase-app-compat.js`);
      await loadScript(`${CDN}/firebase-messaging-compat.js`);
    })();
  }
  return firebaseLoad;
}

/// Prompt for permission, register the SW, mint an FCM token, and store it
/// against the anonymous user in `fcm_tokens`. Returns the resulting permission
/// so the caller can update UI. Best-effort: any failure resolves to the
/// current permission (or "denied") rather than throwing into the vote flow.
export async function enablePush(): Promise<PushPermission> {
  if (!isPushSupported()) return "unsupported";
  try {
    const permission = await Notification.requestPermission();
    if (permission !== "granted") return permission as PushPermission;

    const registration =
      await navigator.serviceWorker.register(SW_URL);
    await navigator.serviceWorker.ready;

    await loadFirebase();
    // window.firebase (compat global) is untyped.
    const fb = (window as unknown as { firebase: any }).firebase;
    if (!fb.apps.length) fb.initializeApp(FIREBASE_CONFIG);
    const messaging = fb.messaging();

    const token: string | null = await messaging.getToken({
      vapidKey: VAPID_KEY,
      serviceWorkerRegistration: registration,
    });
    if (!token) return "granted";

    const session = await ensureSignedIn();
    const uid = session?.user.id;
    if (uid) {
      await supabase
        .from("fcm_tokens")
        .upsert(
          { user_id: uid, token, platform: "web" },
          { onConflict: "token" },
        );
    }
    return "granted";
  } catch {
    // Never let a push hiccup interrupt voting.
    return pushPermission();
  }
}
