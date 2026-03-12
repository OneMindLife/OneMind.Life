// Main load test: ramp from 10 → 100 → 500 VUs over 35 minutes
// Run: k6 run k6/scenarios/02-ramp-up.js

import { sleep } from "k6";
import { COMMON_THRESHOLDS, TEST_PREFIX } from "../config/env.js";
import { getOrCreateAuth, setDisplayName } from "../helpers/auth.js";
import {
  createChat,
  joinChat,
  listTestChats,
  getDashboard,
  submitProposition,
  submitRatings,
} from "../helpers/supabase.js";
import {
  generateChatName,
  generateProposition,
  generateRatings,
} from "../helpers/data.js";

export const options = {
  stages: [
    { duration: "2m", target: 10 },   // Warm up
    { duration: "3m", target: 10 },   // Hold baseline
    { duration: "5m", target: 100 },  // Ramp to 100
    { duration: "5m", target: 100 },  // Hold at 100
    { duration: "5m", target: 500 },  // Ramp to target
    { duration: "10m", target: 500 }, // Hold at target
    { duration: "5m", target: 0 },    // Cool down
  ],
  thresholds: COMMON_THRESHOLDS,
};

// Per-VU state
let _displayName = null;
let _joinedChatId = null;

export default function () {
  const vuId = __VU;
  const iter = __ITER;

  // 1. Sign up once per VU, reuse token across iterations
  const auth = getOrCreateAuth();
  if (!auth) {
    sleep(3);
    return;
  }
  const { access_token, user_id } = auth;

  // 2. Set display name (first iteration only)
  if (!_displayName) {
    _displayName = setDisplayName(access_token, vuId);
    sleep(0.3 + Math.random() * 0.5);
  }

  // 3. Create or join chat (first iteration only)
  let chatId = _joinedChatId;

  if (!chatId) {
    const isCreator = (vuId % 10 === 1);

    if (isCreator) {
      const chatName = generateChatName(vuId, iter);
      const chat = createChat(access_token, chatName);
      if (chat) chatId = chat.id;
    }

    if (!chatId) {
      const testChats = listTestChats(access_token);
      if (testChats.length > 0) {
        const targetChat = testChats[vuId % testChats.length];
        chatId = targetChat.id;
        joinChat(access_token, chatId, _displayName, user_id);
      } else {
        const chatName = generateChatName(vuId, iter);
        const chat = createChat(access_token, chatName);
        if (chat) chatId = chat.id;
      }
    }

    _joinedChatId = chatId;
    sleep(0.5 + Math.random() * 1);
  }

  // 4. Dashboard check — exercises the main RLS-heavy RPC
  getDashboard(access_token, user_id);
  sleep(0.5 + Math.random() * 1);

  // 5. Submit a proposition (exercises submit-proposition edge function)
  //    Passes 0,0 for round/participant — will 400, which is expected
  if (chatId) {
    const proposition = generateProposition(vuId, iter);
    submitProposition(access_token, 0, 0, proposition);
    sleep(0.5 + Math.random() * 0.5);
  }

  // 6. Submit ratings (exercises submit-ratings edge function)
  if (chatId) {
    const mockPropIds = [1, 2, 3];
    const ratings = generateRatings(mockPropIds, vuId);
    submitRatings(access_token, chatId, ratings);
  }

  // Realistic think time between iterations
  sleep(2 + Math.random() * 3);
}
