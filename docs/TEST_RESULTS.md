# OneMind Manual Test Results

**Test Date:** 2026-01-14 (Post Auth Migration)
**Tester:** Developer
**Environment:** Local (Supabase local, Flutter web chrome)

> **Note:** Tests re-verified after migrating from session tokens to Supabase Anonymous Auth (auth.uid()). Realtime kicked user detection now works!

---

## Phase 1: Basic Flow Testing

### Test 1.1: Create Chat with Code Access
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| Create chat form | Appears | ✅ |
| Enter name/topic | Accepted | ✅ |
| Select Code access | 6-char code generated | ✅ |
| Select Manual mode | No timer settings | ✅ |
| Submit | Redirected to chat | ✅ |
| Invite code visible | 6-char code shown | ✅ |
| Host controls | "Start Phase" button visible | ✅ |

---

### Test 1.2: Join Chat via Code
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| Join form | Appears | ✅ |
| Enter code | Accepted | ✅ |
| Enter display name | Accepted | ✅ |
| Submit | Joined chat | ✅ |
| Waiting state | "Waiting for host" shown | ✅ |

**Notes:** Joined with 4 total users (1 host + 3 participants)

---

### Test 1.3: Host Starts Proposing Phase
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| Tap "Start Phase" | Round 1 begins | ✅ |
| Phase badge | Shows "PROPOSING" | ✅ |
| Timer (manual mode) | Not displayed | ✅ |
| Text input | Appears for propositions | ✅ |

---

### Test 1.4: Submit Propositions
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| User A submits | "Build dark mode" saved | ✅ |
| User B submits | "Add notifications" saved | ✅ |
| User C submits | "Fix bugs first" saved | ✅ |
| User D submits | "Improve performance" saved | ✅ |
| Input clears after submit | Yes | ✅ |

**Database verification:** 4 propositions in round 1 (IDs: 1, 2, 3, 5)

---

### Test 1.5: Host Sees All Propositions
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| All propositions visible | 4 shown | ✅ |
| Anonymous (no names) | Content only | ✅ |
| Own marked | "(Your proposition)" label | ✅ |
| Delete buttons on others | Trash icons visible | ✅ |

---

### Test 1.6: Host Advances to Rating
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| Tap "End Proposing" | Phase changes | ✅ |
| Phase badge | Shows "RATING" | ✅ |
| Start Rating button | Appears | ✅ |

---

### Test 1.7: Complete Rating
**Status:** PASS ✅ (verified post-auth-migration)

| Step | Expected | Actual |
|------|----------|--------|
| Grid ranking opens | Yes | ✅ |
| Position propositions | Drag/arrows work | ✅ |
| Submit rankings | Saved | ✅ |
| All 4 users rate | Completed | ✅ |
| Winner shown | "Fix bugs first" | ✅ |
| Consensus progress | "1/2 toward consensus" | ✅ |

**Database verification:**
- 12 grid rankings (4 users × 3 each)
- Round winner: proposition 2, score 100, is_sole_winner=true

---

### Test 1.7b: Round 2 - Carry Forward & Consensus
**Status:** PASS ✅ (verified post-auth-migration 2026-01-14)

| Step | Expected | Actual |
|------|----------|--------|
| Round 2 starts | Proposing phase | ✅ |
| Winner carried forward | Previous winner in round 2 | ✅ |
| carried_from_id set | Points to original winner | ✅ |
| All users rate | Completed | ✅ |
| Same winner | Carried prop wins again | ✅ |
| Consensus reached | 2/2 consecutive sole wins | ✅ |
| Cycle completed | completed_at set | ✅ |

**Database verification (2026-01-14):**
- Cycle 10: completed_at set, winning_proposition_id=6
- Round 10: winning_proposition_id=5, is_sole_winner=true
- Round 11: winning_proposition_id=6 (carried_from_id=5), is_sole_winner=true
- Consensus: 2 consecutive sole wins for same proposition content

---

## Summary

| Phase | Tests | Passed | Failed | Needs Re-Test |
|-------|-------|--------|--------|---------------|
| Phase 1: Basic Flow | 8 | 8 | 0 | 0 |
| Phase 2: Start Mode | 1 | 1 | 0 | 0 |
| Phase 3: Advanced Features | 21 | 14 | 0 | 1 (6 pending) |

**Overall Status:** Core flow verified post-auth-migration ✅ | Email invites E2E working! 🎉

**Completed Manual Tests:**
- ✅ 1.1-1.7b: Basic flow (create, join, propose, rate, consensus, carry-forward)
- ✅ 2.1: Auto mode with timers
- ✅ 3.1: Public access discovery
- ✅ 3.2: Invite-only with email (full E2E: send email → click link → join chat)
- ✅ 3.3: Require approval (host approve/deny, user cancel)
- ✅ 3.4-3.7: Auto-advance (proposing + rating thresholds)
- ✅ 3.10: Multiple propositions per user (full flow with 3 props × 3 users)
- ✅ 3.12: Custom confirmation rounds (single round consensus with confirmation_rounds=1)
- ✅ 3.13: Rating minimum timer extension (timer extends when rating_minimum not met)
- ✅ 3.18-3.19: Tie scenarios (observed during 3.10, both tied winners carried)
- ✅ 3.16: Recurring scheduled chat (full cycle: window open → phases → pause → resume)
- ✅ 3.17: Delete proposition (host can delete, non-host cannot, deleted user can resubmit)
- ✅ 3.20: Leave chat
- ✅ 3.21: Kick user (with realtime)

**Pending Manual Tests:**
- (none)

**N/A - Requires Refactor:**
- ⏭️ 3.15: One-time scheduled start (N/A - `start_mode='scheduled'` is incorrect, see FEATURE_REQUESTS.md)

**Skipped Tests:**
- ⏭️ 3.8-3.9: AI participant (deferred - requires API setup)
- ⏭️ 3.14: Adaptive duration (hidden - oscillation problem, see docs/FEATURE_REQUESTS.md)

**Completed This Session:**
- ✅ 3.11: Show previous results (Bug 21 fixed - winner index clamp)
- ✅ 3.17: Delete proposition (Bug 20 fixed - reactive modal)

**Automated Test Suite:**
- Database tests: 778 passing
- Flutter tests: 1144 passing
- Deno tests: 9 passing (email templates)

---

## Phase 2: Start Mode Testing

### Test 2.1: Auto Mode - Auto-Start on Participant Threshold
**Status:** PASS ✅ (verified post-auth-migration 2026-01-14)

| Step | Expected | Actual |
|------|----------|--------|
| Create auto mode chat | Settings visible | ✅ |
| Set threshold = 3 | Accepted | ✅ |
| Set timers (5 min each) | Accepted | ✅ |
| Host joins (1 participant) | Waiting for participants | ✅ |
| User 2 joins | Still waiting | ✅ |
| User 3 joins (threshold met) | Auto-start cycle/round | ✅ |
| Phase = proposing | Timer running | ✅ |

**Database verification (2026-01-14):**
- Chat 5: start_mode=auto, auto_start_participant_count=3
- Cycle 12 created automatically on 3rd participant join
- Round 13: phase=proposing, phase_ends_at set (timer running)

**Original Fix:** Created `supabase/migrations/20260113000000_add_auto_start_trigger.sql`

**Database Tests:** `supabase/tests/22_auto_start_trigger_test.sql` (11 tests)

---

## Bugs Found

### Bug 1: Auto-Start Trigger Missing (FIXED)
**Date Found:** 2026-01-12
**Severity:** High - Core feature not working
**Status:** FIXED

**Description:** Auto mode chats with `auto_start_participant_count` set would never auto-start. Users had to wait even after threshold was reached.

**Root Cause:** No database trigger existed to watch for participant joins and check if threshold was met.

**Fix:** Added migration `20260113000000_add_auto_start_trigger.sql` with:
- `check_auto_start_on_participant_join()` trigger function
- Trigger fires on INSERT/UPDATE of participants
- Creates cycle + round in 'proposing' phase when threshold met
- Sets `phase_ends_at` for timer-based auto mode

**Verification:**
- 11 database tests pass
- All 657 database tests pass
- All 1048 Flutter tests pass

---

### Bug 2: Proposing Minimum Too Low (FIXED)
**Date Found:** 2026-01-12
**Severity:** Medium - Prevents rating with small groups
**Status:** FIXED

**Description:** When 2 participants each submitted 1 proposition, users got "not enough propositions to rank need at least 2" error because users cannot rate their own propositions. With only 2 total, each user sees only 1 proposition - not enough for grid ranking.

**Root Cause:** Default `proposing_minimum` was 2, but users can't rate their own propositions. With 2 total propositions, each user only sees 1 (excluding their own). Grid ranking requires 2+ propositions to compare.

**Fix:** Created migration `20260113010000_increase_proposing_minimum.sql`:
- Changed constraint from `proposing_minimum >= 2` to `proposing_minimum >= 3`
- Updated default from 2 to 3
- Updated existing chats with `proposing_minimum < 3` to 3
- Added comment explaining the reasoning

**Files Updated:**
- `supabase/migrations/20260113010000_increase_proposing_minimum.sql` (new)
- `supabase/tests/26_proposing_minimum_test.sql` (new, 5 tests)
- `lib/screens/create/models/create_chat_state.dart` - Flutter default changed to 3
- `lib/screens/create/widgets/minimum_advance_section.dart` - UI min constraint set to 3
- Updated 4 existing test files that used `proposing_minimum = 2`

**Verification:**
- 5 new database tests pass (constraint validation)
- All 657 database tests pass
- All 1048 Flutter tests pass

---

### Feature: Round-Minute Timer Alignment (IMPLEMENTED)
**Date:** 2026-01-12
**Status:** COMPLETE

**Problem:** Cron job runs every minute at `:00` seconds. Timers could expire at any second (e.g., `:42`), causing up to 60 second gaps where UI shows "expired" but nothing happens.

**Solution:** Round-minute timer alignment
- All timers now end exactly at `:00` seconds
- Duration is extended (rounded up) to align with cron schedule
- Milliseconds are truncated to prevent extra rounding

**Example:**
- Start at 1:00:42 with 60s duration → ends at 1:02:00 (not 1:01:42)
- Cron runs at 1:02:00 → immediate processing, no gap

**Files Added/Updated:**
- `supabase/migrations/20260113020000_round_minute_timers.sql` - helper function
- `supabase/migrations/20260113030000_fix_round_minute_milliseconds.sql` - millisecond fix
- `lib/services/chat_service.dart` - `calculateRoundMinuteEnd()` helper
- `supabase/functions/process-timers/index.ts` - TypeScript helper
- `supabase/tests/27_round_minute_timers_test.sql` - 6 tests
- `test/services/chat_service_test.dart` - 10 tests

**Manual Verification:**
- Created auto-mode chat with 1 min timer, threshold = 2
- Observed timer extensions: `01:29:00` → `01:34:00` → `01:36:00` → `01:38:00`
- All `phase_ends_at` values ended at `:00` seconds ✓
- Cron job processed expired timers immediately at minute boundary ✓
- Timer extended (not advanced) when proposing minimum not met ✓

**Automated Tests:**
- All 657 database tests pass
- All 1048 Flutter tests pass

---

### Bug 3: Immediate Early Advance Missing (FIXED)
**Date Found:** 2026-01-13
**Severity:** High - Core feature not working as expected
**Status:** FIXED

**Description:** Early advance (auto-advance) feature was waiting for cron job to process instead of triggering immediately when participation threshold was met. This caused up to 60 second delays after threshold was reached.

**Root Cause:** Early advance threshold checking was only implemented in the `process-timers` Edge Function (cron job). No database triggers existed to check thresholds immediately when propositions or ratings were submitted.

**Fix:** Created migration `20260113050000_immediate_early_advance_trigger.sql`:
- `calculate_early_advance_required()` - Helper function to calculate required participation count (MAX of percent and count thresholds)
- `check_early_advance_on_proposition()` - Trigger that fires AFTER INSERT on propositions, advances to rating phase immediately when proposing threshold met
- `check_early_advance_on_rating()` - Trigger that fires AFTER INSERT on grid_rankings, completes round immediately when rating threshold met
- `complete_round_with_winner()` - Helper function to calculate winner and update round

**Behavior:**
- Auto mode with thresholds: Phase advances immediately when threshold met (no waiting for cron)
- Manual mode: No early advance (host controls phases)
- Threshold calculation: MAX(percent_required, count_required) - more restrictive wins
- Cron job still handles timer expiration for non-early-advance scenarios

**Files Added/Updated:**
- `supabase/migrations/20260113040000_increase_threshold_count_minimums.sql` - Constraint enforcement
- `supabase/migrations/20260113050000_immediate_early_advance_trigger.sql` - Trigger implementation
- `supabase/tests/28_immediate_early_advance_test.sql` - 12 tests
- `lib/screens/create/widgets/auto_advance_section.dart` - Added min constraints to UI inputs

**Verification:**
- 12 new database tests pass (immediate early advance)
- All 669 database tests pass
- All 1048 Flutter tests pass

---

### Bug 4: Auto-Start Minimum Participants Too Low (FIXED)
**Date Found:** 2026-01-13
**Severity:** Medium - Could cause unusable chat state
**Status:** FIXED

**Description:** Auto-start participant count could be set to 2, but the system requires at least 3 participants for rating phase to work (users can't rate their own propositions, so with 2 users each sees only 1 proposition - can't rank just 1).

**Root Cause:** No constraint enforcing minimum participant count for auto-start threshold.

**Fix:** Created migration `20260113060000_auto_start_min_3_participants.sql`:
- Added constraint `auto_start_participant_count >= 3`
- Updated existing values below 3 to 3
- Updated Flutter UI min constraint in `phase_start_section.dart`
- Updated related test files to use valid threshold values

**Files Added/Updated:**
- `supabase/migrations/20260113060000_auto_start_min_3_participants.sql` (new)
- `lib/screens/create/widgets/phase_start_section.dart` - min changed from 2 to 3
- `supabase/tests/12_settings_constraints_test.sql` - updated tests
- `supabase/tests/22_auto_start_trigger_test.sql` - updated to use threshold=3
- `supabase/tests/27_round_minute_timers_test.sql` - updated to use threshold=3

**Verification:**
- All 670 database tests pass
- All 1048 Flutter tests pass

---

### Bug 5: RLS DELETE Policy Missing for Participants (FIXED)
**Date Found:** 2026-01-13
**Severity:** High - Leave Chat feature broken
**Status:** FIXED

**Description:** When users clicked "Leave Chat", the participant record was not deleted. The user's UI navigated to "Your Chats" but they remained in the chat (still visible in participants list).

**Root Cause:** No RLS DELETE policy existed for the `participants` table. RLS was enabled but only had SELECT, INSERT, and UPDATE policies. DELETE operations were silently blocked.

**Fix:** Created migration `20260113210000_participant_delete_policy.sql`:
```sql
CREATE POLICY "Participants can leave chat"
ON participants FOR DELETE
USING (
  session_token = get_session_token()
  OR (user_id IS NOT NULL AND user_id = auth.uid())
);
```

**Policy Logic:**
- Anonymous users: Can delete their own record (matched by `session_token`)
- Authenticated users: Can delete their own record (matched by `user_id`)

**Verification:**
- Tests 22-23 in `30_leave_kick_participant_test.sql` verify RLS DELETE policy
- All 710 database tests pass

---

### Bug 6: Realtime DELETE Events Not Filtered by chat_id (FIXED)
**Date Found:** 2026-01-13
**Severity:** High - Realtime not working for participants modal
**Status:** FIXED

**Description:** After implementing Leave Chat (DELETE participant), the host's participants modal was not updating in realtime when users left. The Supabase Realtime subscription with filter `.eq('chat_id', X)` was not receiving DELETE events.

**Root Cause:** The `participants` table had default `REPLICA IDENTITY` (primary key only). When Postgres replicates DELETE events, it only includes columns in the replica identity. With default replica identity, DELETE events only contained `id` (primary key), not `chat_id`. The Supabase Realtime filter `.eq('chat_id', X)` couldn't match because `chat_id` wasn't in the event payload.

**Diagnosis:**
```sql
-- Check replica identity setting
SELECT relname, relreplident
FROM pg_class
WHERE relname = 'participants';
-- Result: relreplident = 'd' (default = primary key only)
```

**Fix:** Created migration `20260113220000_participants_replica_identity_full.sql`:
```sql
ALTER TABLE participants REPLICA IDENTITY FULL;
```

**What REPLICA IDENTITY FULL does:**
- Includes ALL columns in the DELETE event payload (not just primary key)
- Allows Supabase Realtime filters on any column to work correctly
- Required for any table where you filter realtime events by non-PK columns on DELETE

**Verification:**
- DELETE events now include `chat_id` column
- Filter `.eq('chat_id', X)` matches correctly
- Host's participants modal updates immediately when users leave

---

## Phase 3: Pending Manual Tests

### Access & Authentication
| Test | Feature | Settings | Status |
|------|---------|----------|--------|
| 3.1 | Public access | `access_method = 'public'` | PASS ✅ |
| 3.2 | Invite-only access | `access_method = 'invite_only'` | PASS ✅ |
| 3.3 | Require approval | `require_approval = true` | PASS ✅ |

#### Test 3.1: Public Access (Verified 2026-01-14)
- Created chat with `access_method = 'public'`
- Chat appears on Discover page ✅
- Second user can join directly without code ✅

#### Test 3.2: Invite-Only Access (Verified 2026-01-14) ✅ COMPLETE
- Created chat with `access_method = 'invite_only'`
- Chat does NOT appear on Discover page ✅
- Invite record created with `invite_token` ✅
- Email sent via Edge Function with invite link ✅
- Email contains `/join/invite?token=xxx` link ✅
- **Clicked link in email → InviteJoinScreen loaded correctly** ✅
- **User joined chat via link → participant record created** ✅
- **Invite status updated to 'accepted'** ✅

**Database Verification (2026-01-14):**
```
participant_id | display_name | status | chat_name        | invite_status
15             | U2           | active | Test Invite Only | accepted
```

**Email Setup Required:** See `docs/EDGE_FUNCTIONS.md` for local development setup:
- Run Edge Functions with `--no-verify-jwt` flag
- Configure `RESEND_API_KEY` in `supabase/functions/.env`

**Bug Fixed During Testing:** Flutter web URL routing wasn't working for invite links.
- **Root Cause:** Flutter web defaults to hash-based URLs (`/#/path`) but email links use path-based URLs (`/path`)
- **Fix:** Added `usePathUrlStrategy()` to `lib/main.dart` (from `flutter_web_plugins/url_strategy.dart`)
- Also simplified `MaterialApp` initialization to always use `MaterialApp.router` to preserve URL on initial load

**Tests Added:**
- 9 Deno tests for email templates (`supabase/functions/tests/send-email.test.ts`)
- 25 Flutter tests for invite service (`test/services/invite_service_test.dart`)
- Router tests (`test/config/router_test.dart`) - 13 tests for URL routing

#### Test 3.3 Progress: Require Approval Feature

**Implemented:**
- [x] Join request model (`lib/models/join_request.dart`)
- [x] Join request database functions (`approve_join_request`, `cancel_join_request`)
- [x] UI for host to see pending requests (badge + list in chat screen)
- [x] UI for host to approve/deny requests
- [x] UI for requester to see pending requests in "Your Chats"
- [x] UI for requester to cancel pending requests
- [x] Database tests (10 tests for cancel_join_request)
- [x] Flutter tests (10 model tests, 9 UI tests)

**Bug Found:** Realtime updates not working for join requests
- **Root Cause:** RLS policies use `get_session_token()` which reads HTTP headers. Supabase Realtime uses WebSocket connections which don't have access to HTTP headers. `get_session_token()` returns NULL in WebSocket context, causing RLS to fail and no realtime events to be delivered.
- **Solution:** Replace realtime subscriptions with polling (5-second interval). This is simpler, more reliable, and the latency is acceptable for low-frequency join request events.

**Polling Implementation Complete:**
- [x] Host-side: Poll timer in `ChatDetailNotifier` (every 5s)
- [x] Requester-side: Poll timer in `MyChatsNotifier` (every 5s)
- [x] Remove broken realtime subscription code from `participant_service.dart`
- [x] Remove debug print statements
- [x] Delete unnecessary migration file (`20260113210000_realtime_friendly_rls.sql`)

**Verification Steps (after polling implemented):**
1. Create chat with **Require Approval = ON**
2. User 2 requests to join
3. **Host**: Verify badge updates within 5 seconds (no refresh needed)
4. **User 2**: Verify pending request appears in "Your Chats" screen
5. **User 2**: Cancel request, verify removed from list
6. **User 2**: Request again
7. **Host**: Approve request
8. **User 2**: Verify chat appears in "Your Chats" within 5 seconds

**Verified:** 2026-01-13 - All steps passed with polling implementation

### Auto-Advance (Early Advance)
| Test | Feature | Settings | Status |
|------|---------|----------|--------|
| 3.4 | Proposing early advance (%) | `proposing_threshold_percent` | PASS ✅ |
| 3.5 | Proposing early advance (count) | `proposing_threshold_count` | PASS ✅ |
| 3.6 | Rating early advance (%) | `rating_threshold_percent` | PASS ✅ |
| 3.7 | Rating early advance (count) | `rating_threshold_count` | PASS ✅ |

**Verified:** 2026-01-14 (post-auth-migration)
- 12 automated database tests (`28_immediate_early_advance_test.sql`)
- Manual test (2026-01-14): Chat with `proposing_threshold_count=3`, `rating_threshold_count=2`
  - 3 propositions submitted → immediate advance to rating ✅
  - 2 participants rated → winner set immediately, Round 2 created in waiting ✅
- Feature advances phase immediately when threshold met, without waiting for cron

### AI Participant
| Test | Feature | Settings | Status |
|------|---------|----------|--------|
| 3.8 | AI participant enabled | `enable_ai_participant = true` | Skipped |
| 3.9 | AI propositions count | `ai_propositions_count` | Skipped |

> **Note:** AI participant testing deferred - requires API integration setup.

### Other Settings
| Test | Feature | Settings | Status |
|------|---------|----------|--------|
| 3.10 | Multiple propositions per user | `propositions_per_user > 1` | PASS ✅ (full flow verified) |
| 3.11 | Show previous results | `show_previous_results = true` | PASS ✅ |
| 3.12 | Custom confirmation rounds | `confirmation_rounds_required = 1` | PASS ✅ |
| 3.13 | Rating minimum timer extension | `rating_minimum` | PASS ✅ |

#### Test 3.10: Multiple Propositions Per User (Verified 2026-01-14)

**Automated Tests:** 20 database tests in `supabase/tests/11_propositions_per_user_test.sql`

**Verified Behavior:**
- Default `propositions_per_user` is 1 ✅
- Can set custom values (3, 10, etc.) ✅
- Constraint: must be >= 1 (cannot be 0 or negative) ✅
- Each participant has independent count per round ✅
- Count resets per round (new round = fresh limit) ✅
- Limit can be updated mid-chat ✅

**UI Implementation:**
- Shows "$submitted/$limit submitted" counter when limit > 1
- Hides input field after reaching limit
- Button text changes from "Submit" to "Add Proposition" after first submission
- Carried forward propositions don't count against submission limit

**Files:**
- `lib/screens/chat/widgets/phase_panels.dart` - UI implementation
- `lib/screens/create/widgets/proposition_limits_section.dart` - Create chat UI
- `supabase/migrations/20260110030000_add_propositions_per_user.sql` - Schema

**Full Flow Manual Test (2026-01-14):**
- 3 users, each submitting 3 propositions (9 total) ✅
- Rating exclusion: Each user sees only 6 props (excludes own 3) ✅
- MOVDA scoring works correctly with 9 propositions ✅
- Carry-forward: Winner carried to Round 2 ✅
- **Original author exclusion:** User "2" (original author of carried prop) rated only 6 in Round 2 (Host and U3 rated 7) ✅

### Adaptive Duration
| Test | Feature | Settings | Status |
|------|---------|----------|--------|
| 3.14 | Adaptive duration | `adaptive_duration_enabled = true` | SKIPPED ⏭️ (hidden) |

> **Note:** Adaptive duration feature hidden from UI due to oscillation problem. See `docs/FEATURE_REQUESTS.md` for details.

#### Adaptive Duration Test Gap Analysis

The following edge cases were identified as gaps in the original test coverage. Each is necessary to ensure robust adaptive duration behavior:

**Gap 1: Disabled Adaptive Duration No-Op**
- **Why Necessary:** When `adaptive_duration_enabled = FALSE`, the function should return early without modifying any chat durations. Without this test, a regression could cause durations to change even when the feature is disabled.
- **Risk:** Users who don't want adaptive behavior could see unexpected duration changes.
- **Test:** Verify `apply_adaptive_duration()` returns 'disabled' and chat durations remain unchanged.

**Gap 2: Zero Participants**
- **Why Necessary:** Edge case where a round completes with no propositions or ratings (e.g., timer expired with no participation). The function should handle this gracefully without division errors or unexpected behavior.
- **Risk:** Runtime errors or incorrect duration calculations when `v_count = 0`.
- **Test:** Verify function handles zero participation without errors, duration increases (below threshold).

**Gap 3: Compounding Over Multiple Rounds**
- **Why Necessary:** Adaptive duration is designed to adjust over time. Multiple rounds should compound adjustments correctly (300 → 270 → 243). Without testing, rounding errors or bounds violations could accumulate.
- **Risk:** After many rounds, durations could drift to unexpected values or violate min/max bounds.
- **Test:** Run 3+ consecutive rounds, verify durations compound correctly and stay within bounds.

**Gap 4: Different Proposing vs Rating Durations**
- **Why Necessary:** Proposing and rating durations can be configured independently (e.g., 300s proposing, 600s rating). Both should adjust by the same percentage but from their own base values.
- **Risk:** One duration type could be skipped or use the wrong base value.
- **Test:** Set different initial durations, verify both adjust independently by the configured percentage.

**Gap 5: Process-Timers Edge Function Integration**
- **Why Necessary:** The `process-timers` Edge Function calls `apply_adaptive_duration()` after timer expiration. This integration must work correctly in the actual runtime environment, not just in isolated SQL tests.
- **Risk:** Function signature mismatch, missing call, or error handling issues in production.
- **Test:** Verify the Edge Function code correctly calls the SQL function after round completion.
- **Status:** ✅ VERIFIED (code review) - `supabase/functions/process-timers/index.ts:476` calls `applyAdaptiveDuration()` which invokes `apply_adaptive_duration` RPC after `completeRound()`.

#### Adaptive Duration Edge Case Tests (33_adaptive_duration_edge_cases_test.sql)

| Test # | Edge Case | Status |
|--------|-----------|--------|
| 1-3 | Disabled adaptive no-op | ✅ Added |
| 4-6 | Zero participants | ✅ Added |
| 7-11 | Compounding over multiple rounds (600→540→480→420) | ✅ Added |
| 12-16 | Different proposing vs rating durations | ✅ Added |
| 17-20 | Minimum floor during compounding | ✅ Added |

### Scheduled Mode
| Test | Feature | Settings | Status |
|------|---------|----------|--------|
| 3.15 | One-time scheduled start | `start_mode = 'scheduled'`, `schedule_type = 'once'` | N/A ⏭️ (requires refactor) |
| 3.16 | Recurring schedule | `start_mode = 'scheduled'`, `schedule_type = 'recurring'` | PASS ✅ |

**Note:** Test 3.15 marked N/A because `start_mode='scheduled'` conflates two separate concepts. See `docs/FEATURE_REQUESTS.md` for the required refactor to separate facilitation mode from schedule.

#### Test 3.16: Recurring Scheduled Chat (Verified 2026-01-15)

**Setup:**
- `start_mode: 'scheduled'`
- `schedule_type: 'recurring'`
- `schedule_timezone: 'America/New_York'`
- Two schedule windows configured dynamically based on current time
- Proposing/Rating duration: 180 seconds (3 min)
- Rating minimum: 2

**Test Windows (Example):**
- Window 1: Thursday 01:23 - 01:31
- Window 2: Thursday 01:36 - 01:44

**Test Flow:**

| Step | Expected | Actual |
|------|----------|--------|
| Create chat outside window | `schedule_paused = true` | ✅ |
| UI shows "outside schedule window" | ScheduledWaitingPanel displayed | ✅ |
| Window 1 opens (01:23) | `schedule_paused = false`, cycle starts | ✅ |
| Proposing phase starts | Round in proposing, timer running | ✅ |
| Submit 3 propositions | Propositions saved | ✅ |
| Timer expires → rating | Phase advances to rating | ✅ |
| Submit ratings (6 grid rankings) | Ratings saved | ✅ |
| Timer expires → round complete | MOVDA winner calculated | ✅ |
| Round 2 created in proposing | Winner carried forward | ✅ |
| Window 1 closes (01:31) | `schedule_paused = true`, timer saved | ✅ |
| UI shows "outside schedule window" | ScheduledWaitingPanel, shows remaining time | ✅ |
| Window 2 opens (01:36) | `schedule_paused = false`, timer restored | ✅ |
| Proposing timer resumes | phase_ends_at recalculated from saved 120s | ✅ |
| Timer expires → rating | Phase advances to rating with fresh timer | ✅ |

**Window 2 Resume Verification:**
- `schedule_paused` changed from `true` to `false`
- `phase_time_remaining_seconds` cleared (timer now running)
- `phase_ends_at` calculated from saved 120 seconds (06:36:00 + 120s = 06:38:00 UTC)
- UI updated from ScheduledWaitingPanel to ProposingStatePanel

**Key Verifications:**
1. **INSERT Trigger:** New recurring chats correctly set `schedule_paused = true` when created outside window
2. **Pause/Resume:** `process_scheduled_chats()` function correctly pauses/resumes based on window
3. **Timer Preservation:** `phase_time_remaining_seconds` saved on pause, restored on resume
4. **UI Updates:** Chat state updates via Realtime when `schedule_paused` changes

**Bugs Found & Fixed During Testing:**

**Bug 24: schedule_paused Not Set on INSERT (FIXED)**
- New recurring chats were created with `schedule_paused = false` even when outside window
- Fix: Created BEFORE INSERT trigger `set_schedule_paused_on_insert()`
- Migration: `20260115050000_set_schedule_paused_on_insert.sql`
- Tests: `36_schedule_paused_on_insert_test.sql` (6 tests)

**Bug 25: Edge Function Missing Column Reference (FIXED)**
- `process-timers` Edge Function referenced non-existent `adaptive_threshold_count` column
- Error: `column chats_2.adaptive_threshold_count does not exist`
- Fix: Removed stale column reference from `supabase/functions/process-timers/index.ts`

**Bug 26: UI Shows Wrong Panel When Paused With Existing Round (FIXED)**
- When `schedule_paused = true` but a round exists in `waiting` phase, UI showed "Start Phase" button instead of "outside schedule window"
- Root cause: Schedule check only happened when `currentRound == null`
- Fix: Schedule check now happens FIRST, before round phase check
- File: `lib/screens/chat/chat_screen.dart` - `_buildCurrentPhasePanel()`
- Test: `test/screens/chat_screen_test.dart` - "Scheduled Chat - Schedule Paused" group (2 tests)

**Database Verification:**
```sql
-- Check schedule_paused status
SELECT id, schedule_paused, schedule_windows,
       NOW() AT TIME ZONE schedule_timezone as local_now
FROM chats WHERE start_mode = 'scheduled';

-- Check timer preservation on pause
SELECT id, phase, phase_time_remaining_seconds
FROM rounds WHERE completed_at IS NULL;
```

**Files Added/Modified:**
- `supabase/migrations/20260115050000_set_schedule_paused_on_insert.sql` - INSERT trigger
- `supabase/tests/36_schedule_paused_on_insert_test.sql` - 6 pgTAP tests
- `supabase/functions/process-timers/index.ts` - Removed stale column reference
- `lib/screens/chat/chat_screen.dart` - Fixed panel selection priority
- `lib/screens/chat/widgets/phase_panels.dart` - Added scheduleWindows display
- `lib/models/chat.dart` - Added `getNextWindowStart()` method
- `lib/providers/notifiers/chat_detail_notifier.dart` - Added `chat` to state for fresh data
- `test/screens/chat_screen_test.dart` - Added 2 new tests for schedule paused UI

### Host Controls
| Test | Feature | Description | Status |
|------|---------|-------------|--------|
| 3.17 | Delete proposition | Host removes inappropriate content | PASS ✅ |
| 3.20 | Leave Chat | Participant removes themselves from chat | PASS ✅ |
| 3.21 | Kick User | Host removes disruptive participant | PASS ✅ (Realtime works!) |

**Test 3.17 - Delete Proposition (Verified 2026-01-13):**
- Host sees delete icon on all propositions (own + others)
- Non-host users do NOT see delete icon
- Deleted proposition removed from database
- User whose proposition was deleted can submit again

**Test 3.20 - Leave Chat (Verified 2026-01-13):**
- Leave Chat button in app bar menu (participants only)
- Leave action DELETEs participant record
- Host's participants modal updates in realtime
- Left user can rejoin cleanly (no duplicate conflicts)
- 23 database tests pass (`30_leave_kick_participant_test.sql`)

**Test 3.21 - Kick User (Verified 2026-01-13):**
- Kick button visible to host only in participants modal
- Kick action UPDATEs status to 'kicked'
- Kicked user's UI navigates away in realtime
- Kicked user can rejoin (respects `require_approval` setting)
- Host can re-approve kicked user's join request to reactivate

### Edge Cases
| Test | Feature | Description | Status |
|------|---------|-------------|--------|
| 3.18 | Tie scenario | Multiple propositions tie (no sole winner) | PASS ✅ (observed) |
| 3.19 | Consensus reset | Tie breaks consecutive win streak | PASS ✅ (observed) |

#### Test 3.18 & 3.19: Tie Scenarios (Observed During Test 3.10 - 2026-01-14)

**Scenario:** During Test 3.10 (multiple propositions per user), Round 2 ended in a TIE.

**Round 2 Results:**
| Prop ID | Content | Author | MOVDA Score | is_sole_winner |
|---------|---------|--------|-------------|----------------|
| 76 | "2" (new) | User "2" | **76.5** | **false** |
| 74 | "8" (carried from R1) | User "2" | **76.5** | **false** |

**Observed Behavior:**
- Both propositions scored exactly 76.5 (perfect tie)
- `is_sole_winner = false` set for Round 2 winner(s)
- **Both tied winners carried to Round 3** (2 carried propositions)
- Consensus counter reset: Tie breaks the consecutive win streak ✅
- Round 3 will have: 2 carried + (3 users × 3 props) = 11 total propositions

**Why Ties Work This Way:**
- MOVDA scoring produces identical scores when preferences are evenly split
- Neither proposition achieved clear consensus over the other
- Carrying both forward gives them another chance to compete
- This prevents arbitrary tiebreakers from picking "winners" artificially

**Files Verified:**
- `supabase/migrations/20260110040000_add_movda_algorithm.sql` - `is_sole_winner` logic
- `supabase/migrations/20260110042000_carry_forward_winner.sql` - Handles ties in carry-forward

---

## Notes & Observations

1. Manual mode requires host to click to advance each phase (as expected)
2. Carry forward works correctly - winner appears in next round
3. Consensus algorithm working: 2 consecutive wins = consensus
4. New cycle starts fresh after consensus reached

---

## Feature Requests / Future Improvements

### 1. Custom Timer Input
**Priority:** Medium
**Location:** `lib/screens/create/widgets/form_inputs.dart`

**Current:** Timer presets are limited to 1min, 5min, 30min, 1hour, 1day
**Requested:** Allow custom time input (e.g., text field where user can enter X minutes or X hours)

**Workaround:** Added 1min preset for testing purposes

---

### 2. Timer Expiry Loading State
**Priority:** High → **RESOLVED**
**Location:** `lib/screens/chat/chat_screen.dart`

**Problem:** Cron job runs every minute at :00 seconds. When timer expires mid-minute, there's up to 60 seconds delay before phase advances. Users see "expired" but nothing happens - confusing UX.

**Solution Implemented:** Round-minute timer alignment
- All timers now end exactly at `:00` seconds
- Timer duration is extended (rounded up) to align with cron schedule
- Example: Start at 1:00:42 with 60s duration → ends at 1:02:00 (not 1:01:42)
- Cron runs at 1:02:00 → immediate processing, no gap
- Files updated: `chat_service.dart`, `process-timers/index.ts`, database function

---

### 3. Leave Chat Button
**Priority:** Medium → **IMPLEMENTED** ✅
**Location:** `lib/screens/chat/chat_screen.dart`
**Date Completed:** 2026-01-13

**Implementation:**
- Added "Leave Chat" button in app bar menu (participants only, not host)
- Leave action **DELETEs** the participant record entirely
- This allows clean rejoin without duplicate constraint conflicts
- Chat removed from user's "My Chats" list immediately

**Architecture Decision: DELETE on Leave, UPDATE on Kick**

| Action | Database Operation | Rejoin Behavior |
|--------|-------------------|-----------------|
| **Leave** | DELETE record | Can rejoin cleanly (new INSERT) |
| **Kick** | UPDATE status='kicked' | Blocked (existing record), can request approval |

**Files Added/Updated:**
- `lib/services/participant_service.dart` - `leaveChat()` uses DELETE instead of UPDATE
- `supabase/migrations/20260113210000_participant_delete_policy.sql` - RLS DELETE policy
- `supabase/migrations/20260113220000_participants_replica_identity_full.sql` - Required for realtime DELETE events
- `supabase/tests/30_leave_kick_participant_test.sql` - 23 tests for leave/kick/rejoin flows

**Key Technical Details:**
- **RLS DELETE Policy:** Users can only delete their own participant record
- **REPLICA IDENTITY FULL:** Required for Supabase Realtime to filter DELETE events by `chat_id`. Without this, DELETE events only include primary key, and filters like `.eq('chat_id', X)` won't match.
- **Realtime Updates:** Host's participants modal updates immediately when user leaves (uses Consumer widget for reactive updates)

---

### 4. Host Name Disclosure
**Priority:** Medium
**Location:** Create chat flow, join chat preview, database

**Current:** Host creates chat without providing a display name. Participants joining can't see who the host is.
**Requested:**
- Host must enter display name when creating chat (like participants do when joining)
- Join chat preview shows host name so users know who they're joining
- Host name visible in participant list

**Requirements:**
- Add display name field to create chat form
- Store host display name in participants table (already happens, just needs UI)
- Show "Hosted by: [name]" in join preview screen
- Consider: Should host name be shown before or after entering join code?

---

### 5. Kick User (Host Only)
**Priority:** Medium → **IMPLEMENTED** ✅
**Location:** `lib/screens/chat/chat_screen.dart`, database
**Date Completed:** 2026-01-13

**Implementation:**
- Added kick button (person-off icon) in participants modal (host only)
- Kick action **UPDATEs** status to 'kicked' (preserves record to block direct rejoin)
- Kicked user's UI automatically navigates away from chat in realtime
- Kicked user can rejoin based on chat's `require_approval` setting:
  - `require_approval = false`: Kicked user can rejoin directly (reactivates their kicked record)
  - `require_approval = true`: Kicked user must request approval, host can approve to reactivate

**Rejoin Behavior for Kicked Users:**
- Direct rejoin (non-approval chats): `joinChat()` checks for existing 'kicked' record and reactivates via UPDATE
- Approval-based rejoin: `approve_join_request()` function handles reactivation of kicked/left participants
- No special "you were kicked" blocking - respects host's `require_approval` setting

**Files Added/Updated:**
- `lib/screens/chat/chat_screen.dart` - Kick button in participants modal, realtime kicked detection
- `lib/providers/notifiers/chat_detail_notifier.dart` - Refreshes `myParticipant` on participant changes for kick detection
- `lib/services/participant_service.dart` - `joinChat()` reactivates kicked participants
- `lib/screens/join/join_dialog.dart` - Removed `wasKicked` check that blocked rejoining
- `supabase/tests/30_leave_kick_participant_test.sql` - Tests 4-10, 19-21 for kick/reactivation flows

**Realtime Updates:**
- Kicked user navigates away immediately (via `myParticipant` refresh in participant subscription)
- Host's participants modal updates immediately (Consumer widget pattern)

**Edge Cases Handled:**
- Kicked user with pending join request: Request can be approved to reactivate
- Legacy 'left' status records: Handled by `approve_join_request()` for backwards compatibility
- Re-kick after reactivation: Works correctly (status updated to 'kicked' again)

---

### 6. Transition Phase Between Proposing and Rating
**Priority:** Medium
**Location:** Database schema, triggers, Flutter UI

**Current Flow:**
```
Proposing → Rating (immediate transition)
```

**Requested Flow:**
```
Proposing → [Transition/Ready phase] → Rating
```

**Problem:** When proposing ends (timer or early advance), users are immediately thrown into rating UI with no warning or preparation time.

**Proposed Solution:**
- Add optional "transition duration" setting (e.g., 5-30 seconds)
- Show countdown: "Rating starts in X seconds"
- Give users time to mentally prepare for the next phase
- Could also show summary: "3 propositions submitted, ready to rate"

**Implementation Considerations:**
- New phase value in rounds table? (e.g., `phase = 'transitioning'`)
- Or handled purely in UI with a brief delay before showing rating interface?
- Should be configurable per chat (some may want immediate, others want buffer)
- Early advance should still respect transition period

---

### 7. Auto-Kick Inactive Users
**Priority:** Medium
**Location:** Chat settings, database, cron job

**Requested:** Host setting to automatically kick users who don't participate for X consecutive phases (minimum 2 phases). Acts as an automatic cleanup option for hosts who don't want to manually monitor participation.

**Proposed Implementation:**

**Database Schema:**
- Add `auto_kick_threshold` column to `chats` table (nullable integer, minimum 2)
- Add `consecutive_inactive_phases` column to `participants` table (default 0)
- NULL threshold means auto-kick is disabled

**Tracking Logic:**
- After each phase completes, increment `consecutive_inactive_phases` for participants who didn't:
  - Submit a proposition (during proposing phase)
  - Submit a rating (during rating phase)
- Reset counter to 0 when user participates
- When counter >= threshold, auto-kick the user

**Cron Job Update:**
- Add participation check in `process-timers` edge function
- After phase advances, identify inactive participants
- Update their status to 'kicked' if threshold exceeded

**UI Changes:**
- Add toggle in create chat form: "Auto-kick inactive users"
- When enabled, show slider/input for threshold (2-10 phases)
- Show warning in chat: "Inactive for X/Y phases before auto-kick"
- Notification to user before being kicked (at threshold - 1)?

**Edge Cases:**
- User joins mid-cycle: Start counting from next full phase
- Host exemption: Host should never be auto-kicked
- Manual mode chats: Still applicable, counted per phase advancement
- Rejoining after auto-kick: Respects `require_approval` setting like manual kicks

**Files to Modify:**
- `supabase/migrations/YYYYMMDD_auto_kick_inactive.sql` - Schema + trigger/function
- `supabase/functions/process-timers/index.ts` - Auto-kick logic
- `lib/screens/create/create_chat_screen.dart` - Settings UI
- `lib/models/chat.dart` - Add `autoKickThreshold` field
- `lib/services/chat_service.dart` - Pass threshold on create

---

### 8. Prevent Duplicate Propositions (Whitespace Trimming)
**Priority:** Medium
**Location:** Database trigger, Flutter UI validation

**Problem:** Users can submit duplicate propositions in the same round because:
1. Leading/trailing whitespace makes propositions appear different to code but identical to users
2. No duplicate detection exists - same text can be submitted multiple times

**Example:**
- User A submits: `"Fix bugs first"`
- User B submits: `"Fix bugs first "` (trailing space)
- Both are accepted as different propositions, but they're visually identical

**Proposed Solution:**

**1. Whitespace Trimming:**
- Trim leading and trailing whitespace from all propositions before storing
- Apply at database level (trigger) to ensure consistency
- Also apply in Flutter UI for immediate feedback

**2. Duplicate Detection:**
- Before inserting a proposition, check if identical text already exists in the same round
- Case-sensitive exact match (after trimming)
- Reject with clear error message: "This proposition already exists"

**Implementation:**

**Database Trigger:**
```sql
CREATE OR REPLACE FUNCTION trim_and_check_duplicate_proposition()
RETURNS TRIGGER AS $$
BEGIN
    -- Trim whitespace
    NEW.content := TRIM(NEW.content);

    -- Check for duplicate in same round
    IF EXISTS (
        SELECT 1 FROM propositions
        WHERE round_id = NEW.round_id
        AND content = NEW.content
        AND id != COALESCE(NEW.id, -1)
    ) THEN
        RAISE EXCEPTION 'This proposition already exists in this round';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_proposition_trim_duplicate
BEFORE INSERT OR UPDATE ON propositions
FOR EACH ROW EXECUTE FUNCTION trim_and_check_duplicate_proposition();
```

**Flutter Validation:**
- Trim input in `proposition_service.dart` before submission
- Optionally check against already-loaded propositions for immediate feedback
- Show error snackbar if duplicate detected

**Files to Modify:**
- `supabase/migrations/YYYYMMDD_proposition_trim_duplicate.sql` - Trigger
- `lib/services/proposition_service.dart` - Trim before submit
- `lib/screens/chat/widgets/proposition_input.dart` - UI validation/error display

---

### 9. Auto-Show Previous Winner on New Round Start
**Priority:** Low (UX Enhancement)
**Location:** Flutter UI

**Problem:** When a new round starts (round 2+), users land on the proposing view but don't immediately see what won in the previous round. They have to manually navigate to see the carried-forward winner.

**Proposed Solution:**
- When a new round starts (not the first round of a cycle), automatically show/highlight the previous round's winner
- Could be a modal, a highlighted card, or auto-scroll to the carried proposition
- Only applies to rounds where `custom_id > 1` (not the first round of a cycle)

**Implementation Options:**

1. **Modal on round start:** Show a brief modal "Previous winner: [content]" that auto-dismisses or requires tap to continue
2. **Highlight carried proposition:** Visually highlight the carried proposition with a "Previous Winner" badge
3. **Auto-expand results section:** If `show_previous_results` is enabled, auto-expand that section on round start

**Files to Modify:**
- `lib/screens/chat/chat_screen.dart` - Detect new round start, trigger display
- `lib/screens/chat/widgets/` - Add winner highlight/modal component

---

### 10. Fix Chat Created Dialog Width Overflow (FIXED)
**Priority:** Low (UI Bug)
**Location:** Flutter UI
**Status:** FIXED ✅ (2026-01-14)

**Problem:** The invite code Row in the chat created dialog overflows when the dialog is narrow (e.g., on smaller screens). The Row contained a large Text (font size 32 with letter-spacing 8) plus a copy icon.

**Root Cause:** The Row had `mainAxisSize: MainAxisSize.min` but the content (large invite code text + icon) exceeded available width constraints.

**Error from debug.log:**
```
A RenderFlex overflowed by 50 pixels on the right.
Row:file:///...lib/screens/create/dialogs/create_chat_dialogs.dart:182:20
```

**Solution:** Wrapped the Row in a `FittedBox` with `BoxFit.scaleDown` to proportionally scale the content when space is limited.

**Files Modified:**
- `lib/screens/create/dialogs/create_chat_dialogs.dart` - Line 182, wrapped Row in FittedBox

---

### 11. Fix startPhase Race Condition (FIXED)
**Priority:** Medium (Bug)
**Location:** Flutter state management
**Status:** FIXED ✅ (2026-01-14)

**Problem:** Clicking "Start Phase" multiple times quickly creates multiple cycles/rounds because the state doesn't update before the next click. Each click sees `currentCycle == null` and creates a new one.

**Solution Applied:** Added `_isStartingPhase` flag to `ChatDetailNotifier`:
- Flag checked at start of `startPhase()` - returns early if already in progress
- Set to true before async work, reset to false in finally block
- Exposed `isStartingPhase` getter for potential UI button disable

**Files Modified:**
- `lib/providers/notifiers/chat_detail_notifier.dart` - Added flag and guard

---

### 15. Fix UI Not Updating After Own Proposition Submission (FIXED)
**Priority:** Medium (UX Bug)
**Location:** Flutter state management
**Status:** FIXED ✅ (2026-01-14)

**Problem:** After submitting final proposition, user's UI didn't immediately show their submissions. It only updated after another user's action triggered realtime.

**Root Cause:** `submitProposition()` relied on debounced realtime subscription (150ms) to refresh state. When multiple users submit rapidly, the debounce timer keeps resetting, delaying the refresh.

**Solution:** Call `_refreshPropositions()` immediately after submission.

**Files Modified:**
- `lib/providers/notifiers/chat_detail_notifier.dart`

---

### 14. Fix Proposition List Overflow in Host View (FIXED)
**Priority:** Low (UI Bug)
**Location:** Flutter UI
**Status:** FIXED ✅ (2026-01-14)

**Problem:** When there are many propositions, the host's "All Propositions" view overflowed vertically causing a RenderFlex overflow error.

**Root Cause:** The propositions were rendered directly in a Column without any scrolling or height constraints.

**Solution:** Wrapped the propositions list in a `ConstrainedBox` with `maxHeight: 200` and `ListView.builder` for scrolling.

**Files Modified:**
- `lib/screens/chat/widgets/phase_panels.dart` - Host propositions now scroll within 200px container

---

### 13. Fix Proposition Limit Not Enforced (FIXED)
**Priority:** High (Bug)
**Location:** Database trigger
**Status:** FIXED ✅ (2026-01-14)

**Problem:** Users could submit more propositions than the `propositions_per_user` limit allowed.

**Root Cause:** The `enforce_proposition_limit` trigger checked `get_session_token() IS NULL` to skip enforcement. After auth migration to `auth.uid()`, `get_session_token()` always returns NULL, so the limit was never enforced.

**Solution:** Updated trigger to use `auth.uid()` instead of `get_session_token()`:
```sql
-- Old (broken):
IF public.get_session_token() IS NULL THEN RETURN NEW; END IF;

-- New (fixed):
IF auth.uid() IS NULL THEN RETURN NEW; END IF;
```

**Files Modified:**
- `supabase/migrations/20260114170000_fix_proposition_limit_auth_uid.sql`

---

### 16. Fix Previous Results Ordering (FIXED)
**Priority:** Medium (Bug)
**Location:** Flutter service query
**Status:** FIXED (2026-01-14)

**Problem:** In the "Previous Results" view, tied winners appeared out of order. With two propositions tied at 76.5, the display showed:
- #1: "8" (76.5) - winner
- #2: "1" (lower score)
- #3: "2" (76.5) - winner

**Root Cause:** The query in `getPropositionsWithRatings()` used:
```dart
.order('proposition_ratings(rank)', ascending: true)
```
This attempted to order by a joined table column, but PostgREST foreign table ordering doesn't work reliably with embedded resources.

**Fix:** Sort client-side in Dart by `finalRating` descending:
```dart
propositions.sort((a, b) {
  final aRating = a.finalRating ?? 0;
  final bRating = b.finalRating ?? 0;
  return bRating.compareTo(aRating); // Descending
});
```

**Why Tests Didn't Catch This Initially:**
- Flutter service tests mock Supabase (don't execute real queries)
- UI tests use pre-sorted fixture data
- Database tests verify functions, not Flutter query strings

**Tests Now In Place:**
- 3 new tests verify the sorting logic:
  - `sorting logic: orders by finalRating descending`
  - `sorting logic: null ratings sort to end`
  - `sorting logic: ensures tied scores are consecutive` (catches this exact bug)

**Files Modified:**
- `lib/services/proposition_service.dart` - Sort in Dart instead of SQL
- `test/services/proposition_service_test.dart` - 3 new sorting logic tests

---

### 12. Fix Delete Chat Not Working (FIXED)
**Priority:** Medium (Bug)
**Location:** Supabase RLS policy
**Status:** FIXED ✅ (2026-01-14)

**Problem:** Delete chat appeared to succeed but chat remained in list.

**Root Cause:** DELETE policy on `chats` table still used old `creator_session_token` matching:
```sql
USING (creator_session_token = (request.headers->>'x-session-token')::uuid)
```

But we migrated to `auth.uid()`, so the policy never matched and delete silently failed.

**Solution:** Updated policy to use `auth.uid()`:
```sql
USING (creator_id = auth.uid())
```

**Files Modified:**
- `supabase/migrations/20260114040000_fix_chat_delete_policy_auth_uid.sql`

---

### Bug 17: Wrong Table for MOVDA Ratings (FIXED)
**Date Found:** 2026-01-14
**Severity:** High - Results view showed all null ratings
**Status:** FIXED ✅

**Problem:** The "Show Previous Results" feature displayed all propositions with null ratings. Tied winners appeared out of order because sorting by null ratings had undefined behavior.

**Root Cause:** The Flutter code was querying the legacy `proposition_ratings` table which was **empty** in production. The MOVDA algorithm actually populates `proposition_movda_ratings` table.

**Discovery:**
- `proposition_ratings` table was created in initial schema but never populated by any production code
- MOVDA algorithm (migration `20260110040000`) creates and populates `proposition_movda_ratings`
- Old database tests manually INSERT into `proposition_ratings`, masking the bug
- Flutter code queried the empty table, resulting in null ratings for all propositions

**Fix:**
1. Updated `getPropositionsWithRatings()` to query `proposition_movda_ratings` instead of `proposition_ratings`
2. Updated `Proposition.fromJson()` to parse `proposition_movda_ratings` key
3. Dropped unused `proposition_ratings` table via migration
4. Updated Flutter tests and database tests to use correct table

**Files Modified:**
- `lib/services/proposition_service.dart` - Query `proposition_movda_ratings`
- `lib/models/proposition.dart` - Parse `proposition_movda_ratings`
- `test/models/proposition_test.dart` - Use `proposition_movda_ratings` key
- `test/fixtures/proposition_fixtures.dart` - Use `proposition_movda_ratings` key
- `supabase/migrations/20260114134745_drop_unused_proposition_ratings.sql` - Drop legacy table
- `supabase/tests/00_schema_test.sql` - Remove proposition_ratings table tests
- `supabase/tests/03_consensus_test.sql` - Use `proposition_movda_ratings`
- `supabase/tests/07_ratings_test.sql` - Use `proposition_movda_ratings`
- `supabase/tests/09_phase_transitions_test.sql` - Use `proposition_movda_ratings`

**Verification:**
- All 716 database tests pass
- All 23 Flutter proposition tests pass
- Manual test: Tied winners now correctly appear at positions #1 and #2 with correct scores

**Lesson Learned:** Test data fixtures should match production data flow. The old tests manually INSERT into `proposition_ratings` but production code uses MOVDA which populates `proposition_movda_ratings`.

---

### Bug 18: Phase Sync - U3 Doesn't See Phase Change (FIXED)
**Date Found:** 2026-01-14
**Severity:** High - Other participants stuck on old phase
**Status:** FIXED ✅

**Problem:** When host advances from proposing phase to rating phase, other participants (U3) sometimes don't see the UI update. They remain stuck on the proposing/submissions view while the host is already in rating.

**Root Causes:**
1. Rate limiting was **dropping** refresh requests instead of **deferring** them
2. No direct state update from Realtime payload (relied only on full refresh)

**Fixes Applied:**
1. Rate limiting now defers instead of drops - if a refresh is requested while rate-limited, it schedules a deferred refresh after the cooldown
2. Added `_onRoundChange()` method that updates state directly from Realtime payload without waiting for full refresh
3. Added post-subscription refresh (200ms delay) to catch events that fired during initial load

**Code Changes (chat_detail_notifier.dart):**
```dart
// Before: dropped requests
if (now.difference(_lastRefreshTime!) < _minRefreshInterval) {
  return;  // ❌ DROPPED
}

// After: defers requests
if (now.difference(_lastRefreshTime!) < _minRefreshInterval) {
  _refreshDebounce = Timer(delay, () => _loadData());  // ✅ DEFERRED
  return;
}
```

**Files Modified:**
- `lib/providers/notifiers/chat_detail_notifier.dart` - Rate limiting defer, direct state update
- `lib/models/round.dart` - Added `copyWith()` method for immutable updates
- `test/providers/notifiers/chat_detail_notifier_test.dart` - 8 new tests

**Verification:**
- Manual test with 2 browser windows PASSED
- All 8 phase sync tests pass
- U3 immediately sees rating grid when host advances

**Full Investigation:** See `docs/INVESTIGATION_PHASE_SYNC.md`

---

### Bug 19: Grid Compression Detection Not Working (FIXED)
**Date Found:** 2026-01-14
**Severity:** Medium - Only newly placed proposition sent to DB instead of all
**Status:** FIXED ✅

**Problem:** When dragging a proposition past the 0-100 boundary causes other propositions to compress, the `allPositionsChanged` flag was incorrectly `false`. This meant only the newly placed proposition was sent to the database, not the ones that shifted.

**Root Cause:** The `positionsBefore` map was captured **after** compression had already happened during the drag, not **before** the placement started.

```dart
// BUG: This captured positions AFTER compression happened during drag
final positionsBefore = <String, double>{};
for (var prop in _rankedPropositions) {
  if (!prop.isActive) positionsBefore[prop.id] = prop.position;
}
```

**Fix:** Added `_positionsAtPlacementStart` field to capture positions at the START of the placement (when the card first becomes active), before any dragging occurs.

```dart
/// Positions of inactive cards at the START of the current placement
final Map<String, double> _positionsAtPlacementStart = {};

void _addNextProposition() {
  // Capture positions at the START of this placement (before any dragging)
  _positionsAtPlacementStart.clear();
  for (var prop in _rankedPropositions) {
    if (!prop.isActive) {
      _positionsAtPlacementStart[prop.id] = prop.position;
    }
  }
}
```

**Files Modified:**
- `lib/widgets/grid_ranking/grid_ranking_model.dart` - Track positions at placement start
- `test/widgets/grid_ranking/grid_ranking_model_test.dart` - New test for compression detection

**Verification:**
- New test `sends ALL rankings when dragging past boundary causes compression` passes
- All 61 grid ranking tests pass
- Compression correctly detected: `allPositionsChanged = true` when positions shift

---

### Performance: Remove MOVDA Trigger (DONE)
**Date:** 2026-01-14
**Type:** Performance Optimization
**Status:** COMPLETE ✅

**Problem:** The trigger `trg_recalculate_movda_on_grid_insert` fired on every `grid_rankings` INSERT, causing:
- Redundant MOVDA calculations during active rating phase
- Performance issues and potential timeouts with many participants
- MOVDA was ALSO called at phase end in `process-timers`, making the trigger redundant

**Solution:** Remove the trigger entirely. MOVDA now only runs once when rating phase ends:
- `process-timers` edge function calls `calculate_movda_scores_for_round()` when timer expires
- `ChatService.completeRatingPhase()` calls it when host manually ends rating

**Files Modified:**
- `supabase/migrations/20260114163247_remove_movda_trigger_on_grid_insert.sql` - Drop trigger
- `supabase/tests/13_movda_algorithm_test.sql` - Remove trigger tests, update plan count (42→40)
- `supabase/tests/17_tiebreaker_test.sql` - Remove trigger disable/enable calls

**Verification:**
- All 714 database tests pass
- All 1128 Flutter tests pass
- MOVDA scores only appear after rating phase completes (not during)

---

### Performance: Grid Ranking Submission Optimization (ALREADY IMPLEMENTED)
**Date:** 2026-01-14 (verified)
**Type:** Performance Optimization
**Status:** COMPLETE ✅

**Optimization:** Grid ranking submissions now send only the newly placed proposition instead of all propositions, unless compression/expansion happened.

- **No compression:** Sends 1 row (just the new proposition)
- **Compression happened:** Sends all rows (positions shifted)

**Implementation:**
- `GridRankingModel._saveCurrentRankings()` checks `allPositionsChanged` flag
- `_lastPlacedId` tracks which proposition was just placed
- `PropositionService.submitGridRankings()` uses upsert to handle partial updates

**Test:** `sends only new proposition when no compression happens` (line 1069)

---

### Bug 20: Host Proposition Modal Not Reactive (FIXED)
**Date Found:** 2026-01-14
**Severity:** Medium - Modal showed stale data
**Status:** FIXED ✅

**Problem:** The host's "All Propositions" bottom sheet had two issues:
1. After deleting a proposition, the modal still showed the deleted item
2. When participants submitted new propositions, the modal didn't update

**Root Cause:** The modal was built once with a static list and never rebuilt when state changed. ProposingStatePanel directly created the modal using the `allPropositions` list passed at construction time.

**Fix:** Refactored to use best practice architecture:
1. Move modal logic from `phase_panels.dart` to `chat_screen.dart`
2. Use `Consumer` widget inside modal to watch `chatDetailProvider`
3. Modal content now rebuilds when state changes
4. Delete confirmation no longer closes modal - lets it update reactively

```dart
// Before: Static modal built once
showModalBottomSheet(
  builder: (_) => Column(children: allPropositions.map(...))
);

// After: Reactive modal with Consumer
showModalBottomSheet(
  builder: (sheetContext) => Consumer(
    builder: (context, ref, _) {
      final stateAsync = ref.watch(chatDetailProvider(_params));
      return stateAsync.when(
        data: (state) => _buildPropositionsSheetContent(state, sheetContext),
        ...
      );
    },
  ),
);
```

**Files Modified:**
- `lib/screens/chat/chat_screen.dart` - Added reactive modal with Consumer
- `lib/screens/chat/widgets/phase_panels.dart` - Now presentational, uses callback
- `test/screens/chat/widgets/phase_panels_test.dart` - Updated for new API

**Verification:**
- Modal updates immediately when participant submits proposition
- Modal updates after deleting a proposition (stays open)
- All 1128 Flutter tests pass

---

### Bug 21: Winner Index Out of Bounds After Tie Resolves (FIXED)
**Date Found:** 2026-01-14
**Severity:** High - App crash (RangeError)
**Status:** FIXED ✅

**Problem:** When navigating through tied winners (e.g., viewing the 3rd winner at index=2), then advancing to a new round with fewer winners (e.g., sole winner), the app crashed with:
```
RangeError (index): Index out of range: index should be less than 1: 2
```

**Scenario:**
1. Round 1 ends with 3-way tie (all scores = 50)
2. User navigates to view 3rd winner (index = 2)
3. Round 2 ends with sole winner (1 winner)
4. Previous Winner panel tries to access index 2 of a 1-item list → crash

**Root Cause:** `_currentWinnerIndex` was stored in widget state but never reset or clamped when the winners list changed.

**Fix:** Clamp the index to valid range before passing to `PreviousWinnerPanel`:
```dart
final clampedIndex = state.previousRoundWinners.isEmpty
    ? 0
    : _currentWinnerIndex.clamp(0, state.previousRoundWinners.length - 1);
```

**Files Modified:**
- `lib/screens/chat/chat_screen.dart` - Clamp winner index before use

**Verification:**
- No crash when tie resolves to sole winner
- All 1128 Flutter tests pass

---

### Bug 22: Timer Extension UI Not Updating (FIXED)
**Date Found:** 2026-01-14
**Severity:** Medium - Users saw "Time expired" when timer was actually extended
**Status:** FIXED ✅

**Problem:** When the rating minimum wasn't met and the timer was extended in the database, the UI continued showing "Time expired" instead of the new countdown.

**Root Causes:**
1. `CountdownTimer.onExpired` condition used `>= 0` which fired repeatedly when `_remaining == 0`
2. `ChatDetailNotifier._cachedState` was never populated, so during loading states the realtime handler couldn't update state

**Fixes Applied:**
1. Changed `countdown_timer.dart` condition from `>= 0` to `> 0` to prevent infinite callbacks
2. Populated `_cachedState` in `_loadData()` and `_onRoundChange()` methods

**Files Modified:**
- `lib/widgets/countdown_timer.dart` - Fix onExpired condition
- `lib/providers/notifiers/chat_detail_notifier.dart` - Populate _cachedState
- `test/widgets/countdown_timer_test.dart` - New tests for the fix
- `test/providers/notifiers/chat_detail_notifier_test.dart` - Timer extension tests

**Verification:**
- Timer extension now updates UI correctly
- CountdownTimer no longer causes infinite refresh loop
- All tests pass

---

### Bug 23: Proposing Minimum Includes Carried Forward Propositions (FIXED)
**Date Found:** 2026-01-14
**Severity:** Medium - Minimum could be met with only carried propositions
**Status:** FIXED ✅

**Problem:** When checking if `proposing_minimum` is met to advance from proposing to rating phase, the count included carried forward propositions (previous round winners). This inflated the count unfairly.

**Example:** If `proposing_minimum = 3` and 2 propositions were carried forward, only 1 new proposition would be needed - defeating the purpose of the minimum.

**Fix:** Added filter to exclude propositions where `carried_from_id IS NOT NULL`:
```typescript
const { count, error } = await supabase
  .from("propositions")
  .select("id", { count: "exact", head: true })
  .eq("round_id", roundId)
  .is("carried_from_id", null);  // Exclude carried forward
```

**Files Modified:**
- `supabase/functions/process-timers/index.ts` - Filter out carried forward in checkMinimumMet()
- `supabase/tests/31_proposing_min_excludes_carried_test.sql` - 6 new tests
- `CLAUDE.md` - Documented carry forward rules

**Verification:**
- 6 new pgTAP tests pass
- Proposing minimum now only counts NEW propositions

---

#### Test 3.13: Rating Minimum Timer Extension (Verified 2026-01-14)

**Setup:**
- Timed mode ON
- Proposing duration: 60s
- Rating duration: 60s
- Rating minimum: 2
- Proposing minimum: 3
- 3 users, each submitted 1 proposition

**Test Flow:**
1. Started rating phase
2. Only 1 user rated (avg ratings < 2)
3. Timer expired
4. **Expected:** Timer extends by `rating_duration`

**Result:** PASS ✅
- Timer correctly extended when rating_minimum not met
- UI updated to show new countdown (after Bug 22 fix)
- Cron job processed extension at minute boundary

**Database Verification:**
```sql
SELECT id, phase, phase_ends_at, NOW() as current_time
FROM rounds WHERE completed_at IS NULL;
-- phase_ends_at was extended by rating_duration_seconds
```

---

#### Test 3.12: Custom Confirmation Rounds (Verified 2026-01-14)

**Setup:**
- `confirmation_rounds_required: 1` (instead of default 2)
- Manual mode
- 3 participants

**Test Flow:**
1. 3 users submitted propositions
2. Advanced to rating phase
3. All users rated
4. Round 1 winner determined

**Result:** PASS ✅
- Consensus reached immediately after Round 1 (no Round 2 needed)
- Cycle completed with `winning_proposition_id` set
- New cycle auto-started

**Database Verification:**
```sql
SELECT c.confirmation_rounds_required, cy.completed_at, r.custom_id as round_num
FROM chats c
JOIN cycles cy ON cy.chat_id = c.id
JOIN rounds r ON r.cycle_id = cy.id
WHERE c.confirmation_rounds_required = 1;

-- Result: Cycle completed after round 1, is_sole_winner = true
```
