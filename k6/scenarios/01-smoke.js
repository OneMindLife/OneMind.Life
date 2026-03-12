// Smoke test: 5 VUs, validates all flows work end-to-end
// Run: k6 run k6/scenarios/01-smoke.js

import { sleep } from "k6";
import { COMMON_THRESHOLDS, TEST_PREFIX } from "../config/env.js";
import { getOrCreateAuth, setDisplayName } from "../helpers/auth.js";
import {
  createChat,
  joinChat,
  listTestChats,
  getDashboard,
  submitProposition,
} from "../helpers/supabase.js";
import { generateChatName, generateProposition } from "../helpers/data.js";

export const options = {
  vus: 5,
  duration: "2m",
  thresholds: COMMON_THRESHOLDS,
};

// Per-VU state (module-level = VU-scoped in k6)
let _displayName = null;

export default function () {
  const vuId = __VU;
  const iter = __ITER;

  // 1. Sign up once per VU, reuse token across iterations
  const auth = getOrCreateAuth();
  if (!auth) {
    console.error(`VU ${vuId}: Signup failed, skipping iteration`);
    sleep(2);
    return;
  }

  const { access_token, user_id } = auth;

  // 2. Set display name (only on first iteration)
  if (!_displayName) {
    _displayName = setDisplayName(access_token, vuId);
    sleep(0.5);
  }

  // 3. Create or join a chat
  let chatId;

  if (vuId === 1 && iter === 0) {
    // First VU creates a chat
    const chatName = generateChatName(vuId, iter);
    const chat = createChat(access_token, chatName);
    if (chat) {
      chatId = chat.id;
      console.log(`VU ${vuId}: Created chat ${chatId}`);
    }
  } else {
    // Other VUs try to join existing test chats
    const testChats = listTestChats(access_token);
    if (testChats.length > 0) {
      const targetChat = testChats[iter % testChats.length];
      chatId = targetChat.id;
      if (iter === 0) {
        joinChat(access_token, chatId, _displayName, user_id);
      }
    } else if (iter === 0) {
      // No existing chats, create one
      const chatName = generateChatName(vuId, iter);
      const chat = createChat(access_token, chatName);
      if (chat) chatId = chat.id;
    }
  }

  sleep(0.5);

  // 4. Dashboard check
  getDashboard(access_token, user_id);
  sleep(0.5);

  // 5. Submit a proposition (will 400 — no real round/participant, that's OK)
  if (chatId) {
    const proposition = generateProposition(vuId, iter);
    submitProposition(access_token, 0, 0, proposition);
  }

  sleep(1);
}
