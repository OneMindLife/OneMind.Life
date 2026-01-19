# OneMind Testing Plan

Comprehensive manual testing plan covering all use cases, user types, and feature combinations.

---

## Test Environment Setup

### Prerequisites
- [ ] Supabase local instance running (`npx supabase start`)
- [ ] Flutter app running (`flutter run`)
- [ ] Multiple browser windows/devices for multi-user testing

### Test Accounts
| User | Type | Purpose |
|------|------|---------|
| User A | Anonymous | Host, creates chats |
| User B | Anonymous | Participant, joins chats |
| User C | Anonymous | Participant, joins chats |
| User D | Anonymous | Observer, tests discovery |

---

## Phase 1: Basic Flow Testing

### Test 1.1: Create Chat with Code Access
**Scenario:** Host creates a private chat with invite code

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Open app as User A | Home screen loads |
| 2 | Tap "Create Chat" | Create chat form appears |
| 3 | Enter name: "Team Decision" | - |
| 4 | Enter topic: "What feature should we build next?" | - |
| 5 | Select access: "Code" | 6-character code will be generated |
| 6 | Select start mode: "Manual" | No timer settings shown |
| 7 | Submit | Chat created, redirected to chat screen |
| 8 | Verify invite code shown | 6-char code visible (e.g., "A7X3K9") |
| 9 | Verify "Start Phase" button visible | Host controls visible |

### Test 1.2: Join Chat via Code
**Scenario:** Participant joins using invite code

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Open app as User B | Home screen loads |
| 2 | Tap "Join Chat" | Join form appears |
| 3 | Enter code from Test 1.1 | - |
| 4 | Enter display name: "Bob" | - |
| 5 | Submit | Joined chat, see waiting state |
| 6 | Verify "Waiting for host" message | Non-host cannot start |

### Test 1.3: Host Starts Proposing Phase
**Scenario:** Host initiates the first round

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As User A (host), tap "Start Phase" | Round 1 begins |
| 2 | Verify phase badge shows "PROPOSING" | Blue badge in app bar |
| 3 | Verify NO timer displayed (manual mode) | Timer area empty |
| 4 | Verify text input appears | Can type proposition |

### Test 1.4: Submit Propositions
**Scenario:** Multiple users submit propositions

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As User A, enter "Build dark mode" | - |
| 2 | Tap Submit | Proposition saved, input clears |
| 3 | Verify "Your Propositions" shows submission | Card with content visible |
| 4 | As User B, enter "Add notifications" | - |
| 5 | Tap Submit | Proposition saved |
| 6 | As User C, join and submit "Fix bugs first" | Third proposition added |

### Test 1.5: Host Sees All Propositions (Moderation)
**Scenario:** Host can moderate content during proposing

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As User A (host), scroll down | "All Propositions (3)" section visible |
| 2 | Verify all 3 propositions shown | Content visible, NO names shown |
| 3 | Verify "(Your proposition)" label on own | Host's submission marked |
| 4 | Verify delete buttons on others' propositions | Trash icons visible |
| 5 | Tap delete on one proposition | Confirmation dialog appears |
| 6 | Cancel deletion | Proposition still exists |

### Test 1.6: Host Advances to Rating
**Scenario:** Host manually ends proposing phase

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As User A, tap "End Proposing & Start Rating" | Phase changes |
| 2 | Verify phase badge shows "RATING" | Purple badge |
| 3 | Verify "Start Rating" button appears | For users who haven't rated |
| 4 | As User A, tap "Start Rating" | Grid ranking screen opens |

### Test 1.7: Complete Rating
**Scenario:** Users rate all propositions

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | In grid ranking, position propositions | Drag to rank |
| 2 | Tap "Submit Rankings" | Rankings saved |
| 3 | Verify "Current Leader" section shows | Leading proposition visible |
| 4 | Repeat for User B and User C | All users rate |

---

## Phase 2: Start Mode Testing

### Test 2.1: Auto Mode with Timers
**Scenario:** Chat with automatic phase advancement

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with start_mode: "Auto" | Timer settings visible |
| 2 | Set proposing duration: 5 minutes | - |
| 3 | Set rating duration: 5 minutes | - |
| 4 | Set auto_start_participant_count: 2 | - |
| 5 | Create chat | Chat in waiting state |
| 6 | Join with User B | 2 participants now |
| 7 | Verify round auto-starts | Proposing phase begins |
| 8 | Verify countdown timer visible | Shows time remaining |
| 9 | Verify host can still advance early | "End Proposing" button works |

### Test 2.2: Manual Mode (No Timers)
**Scenario:** Verify fully manual mode has no timers

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with start_mode: "Manual" | No timer settings |
| 2 | Start phase | Proposing begins |
| 3 | Verify NO countdown timer | Timer area empty |
| 4 | Wait indefinitely | Phase doesn't auto-advance |
| 5 | Host must click to advance | Manual control only |

### Test 2.3: Scheduled Mode - One-Time
**Scenario:** Chat scheduled for specific time (one-time schedule)

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with start_mode: "Scheduled" | Schedule settings appear |
| 2 | Select schedule type: "One-time" | Date/time picker shown |
| 3 | Select timezone from dropdown | Timezone selector with search |
| 4 | Set start time ~2 minutes in future | Date and time selected |
| 5 | Create chat | Chat created, redirected to chat screen |
| 6 | Verify "Scheduled" panel appears | NOT "Start Phase" button |
| 7 | Verify panel shows "Scheduled to start" | With formatted date/time |
| 8 | Verify time is in LOCAL timezone | e.g., "1/15 at 11:38 PM" not UTC |
| 9 | Verify timezone display shown | e.g., "New York" |
| 10 | Wait for scheduled time to arrive | Timer auto-refreshes UI |
| 11 | Verify UI changes to "Start Phase" | Host can now start |
| 12 | Host starts phase | Round 1 begins |

### Test 2.3b: Scheduled Mode - Recurring *(Needs Testing)*
**Scenario:** Chat with recurring schedule windows

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with start_mode: "Scheduled" | Schedule settings appear |
| 2 | Select schedule type: "Recurring" | Window editor shown |
| 3 | Select timezone from dropdown | Timezone selector with search |
| 4 | Configure window outside current time | e.g., Monday 9am-5pm if it's Sunday |
| 5 | Create chat | Chat created |
| 6 | Verify "Scheduled" panel appears | Shows "outside schedule window" |
| 7 | Verify "Next window starts" message | If nextWindowStart available |
| 8 | Verify timezone display shown | e.g., "New York" |
| 9 | Test "Hide when outside schedule" toggle | Chat visibility setting |
| 10 | (Within schedule window) Verify starts | Round can begin |

---

## Phase 3: Access Method Testing

### Test 3.1: Public Chat Discovery
**Scenario:** Public chat appears in Discover

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with access_method: "Public" | Chat created |
| 2 | As User D, go to Discover screen | List of public chats |
| 3 | Verify new chat appears in list | Chat visible with name/description |
| 4 | Tap to join | Join flow starts |
| 5 | After joining, verify chat removed from Discover | Filters out joined chats |

### Test 3.2: Code Access (Private)
**Scenario:** Code-access chat NOT in Discover

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with access_method: "Code" | Chat created |
| 2 | As User D, go to Discover screen | - |
| 3 | Verify chat does NOT appear | Private chats hidden |
| 4 | Use "Join Chat" with code | Can join via code |

### Test 3.3: Invite Only (Email)
**Scenario:** Email-only access

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with access_method: "Invite Only" | Invite settings appear |
| 2 | Add email invitations | - |
| 3 | Verify no code shown | No invite code |
| 4 | Verify not in Discover | Not discoverable |
| 5 | Invited user can join via email link | Token-based access |

---

## Phase 4: Constraint Testing

### Test 4.1: Minimum Propositions
**Scenario:** Cannot advance without enough propositions

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with proposing_minimum: 2 | - |
| 2 | Start proposing phase | - |
| 3 | Submit only 1 proposition | - |
| 4 | Try to advance to rating | Error: "Need at least 2 propositions" |
| 5 | Submit second proposition | - |
| 6 | Advance to rating | Success |

### Test 4.2: Propositions Per User Limit
**Scenario:** User can only submit allowed number

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with propositions_per_user: 3 | - |
| 2 | Submit first proposition | "1/3 submitted" shown |
| 3 | Submit second proposition | "2/3 submitted" |
| 4 | Submit third proposition | "3/3 submitted" |
| 5 | Try to submit fourth | Input disabled or error |

### Test 4.3: Minimum Participants for Rating
**Scenario:** Need 3+ participants for rating to work

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with only 2 participants | - |
| 2 | Both submit propositions | 2 propositions |
| 3 | Advance to rating | - |
| 4 | Each user can only rate 1 proposition | Can't rate own |
| 5 | rating_minimum of 2 cannot be met | Warning or blocked |

---

## Phase 5: Host Powers Testing

### Test 5.1: Host Can Delete Propositions
**Scenario:** Moderation during proposing

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As host, view all propositions | All visible |
| 2 | Tap delete on inappropriate one | Confirmation dialog |
| 3 | Confirm deletion | Proposition removed |
| 4 | Verify count decreases | "All Propositions (N-1)" |

### Test 5.2: Host Cannot Delete During Rating
**Scenario:** Propositions locked once rating starts

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Advance to rating phase | - |
| 2 | As host, check propositions | Delete buttons NOT shown |
| 3 | Propositions are locked | Cannot modify |

### Test 5.3: Host Cannot See Who Submitted
**Scenario:** Anonymity preserved

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As host, view all propositions | Content visible |
| 2 | Verify NO usernames shown | Anonymous submissions |
| 3 | Only "(Your proposition)" marked | Host knows their own |

### Test 5.4: QR Code Sharing
**Scenario:** Host can share QR code

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As host of code-access chat | - |
| 2 | Tap QR code icon in app bar | QR dialog appears |
| 3 | Verify code embedded in QR | Scannable |
| 4 | Share or copy code | Works |

---

## Phase 6: Consensus Testing

### Test 6.1: Single Round Consensus
**Scenario:** confirmation_rounds_required: 1

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with confirmation_rounds: 1 | - |
| 2 | Complete proposing and rating | - |
| 3 | Winner determined | Consensus reached immediately |
| 4 | New cycle starts | Fresh round begins |

### Test 6.2: Two Round Consensus (Default)
**Scenario:** Same proposition must win twice

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with confirmation_rounds: 2 | Default |
| 2 | Complete Round 1 | Winner shown, "1/2 wins" |
| 3 | Complete Round 2 with same winner | Consensus! |
| 4 | Verify consensus item added to history | Displayed in chat |

### Test 6.3: Tie Breaks Chain
**Scenario:** Tie doesn't count toward consensus

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Round 1: Proposition A wins | "1/2 wins" |
| 2 | Round 2: Tie between A and B | Tie shown, chain broken |
| 3 | Round 3: Proposition A wins | "1/2 wins" (reset) |
| 4 | Round 4: Proposition A wins | Consensus (2 in a row) |

---

## Phase 7: Edge Cases

### Test 7.1: Empty Proposing Phase
**Scenario:** No propositions submitted

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Start proposing phase | - |
| 2 | No one submits | 0 propositions |
| 3 | Try to advance | Error: need 2+ propositions |

### Test 7.2: User Leaves Mid-Round
**Scenario:** Participant leaves during rating

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | User B in rating phase | - |
| 2 | User B closes app/leaves | - |
| 3 | Round continues | Other users can still rate |
| 4 | Ratings calculated without User B | Partial participation OK |

### Test 7.3: Host Leaves
**Scenario:** Host abandons chat

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Host creates chat, starts round | - |
| 2 | Host leaves/closes app | - |
| 3 | In manual mode | Phase stuck (no timer) |
| 4 | In auto mode | Timer still runs |

### Test 7.4: Network Disconnection
**Scenario:** Brief connectivity loss

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | User in chat | - |
| 2 | Disable network briefly | - |
| 3 | Re-enable network | - |
| 4 | Verify state refreshes | Real-time resync |

---

## Phase 8: Multi-Use Case Scenarios

> These scenarios validate configurations from [USE_CASES.md](./USE_CASES.md). Each test maps to a documented use case.

### Test 8.1: Quick Poll (Friends Dinner)
**Settings:** code access, manual mode, 1 confirmation round, 5 min timers

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create "Where to eat?" chat | - |
| 2 | Share code in group chat | Friends join |
| 3 | Everyone proposes restaurants | Multiple options |
| 4 | Quick rating | Winner chosen fast |
| 5 | Decision made | Single round winner |

### Test 8.2: Team Decision (Sprint Planning)
**Settings:** code access, auto mode, 2 confirmation rounds, 1 hour timers

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create "Q2 Priorities" chat | - |
| 2 | Team joins via code | - |
| 3 | Async proposing (1 hour) | People submit when available |
| 4 | Rating phase auto-starts | Timer-driven |
| 5 | Consensus after 2 rounds | Confirmed decision |

### Test 8.3: Classroom Exercise
**Settings:** code access, auto mode (20 students), 3 props per user, 15 min timers

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Teacher creates chat | - |
| 2 | Display code on screen | Students join |
| 3 | Auto-starts at 20 students | Round begins |
| 4 | Students submit 3 ideas each | Many propositions |
| 5 | Rating phase | Best ideas rise |

### Test 8.4: Public Community Forum
**Settings:** public access, auto mode, 2 confirmation rounds, 1 day timers

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create public chat "Book of the Month" | - |
| 2 | Anyone can find in Discover | - |
| 3 | Community joins over time | - |
| 4 | Day-long proposing | Async participation |
| 5 | Consensus emerges | Community decision |

---

## Phase 9: Grid Ranking Features

### Test 9.1: Save-As-You-Go Rankings
**Scenario:** Rankings auto-save after each placement

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Start rating, open grid ranking | Binary phase |
| 2 | Place first two propositions | Confirm binary |
| 3 | Place third proposition | Rankings saved to DB |
| 4 | Check `grid_rankings` table | 3 rows with positions |
| 5 | Place fourth proposition | 4 rows in DB |

### Test 9.2: Resume From Saved Rankings
**Scenario:** User can return to incomplete rating

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Place 2-3 propositions in grid | Auto-saved |
| 2 | Click back / leave grid ranking | Return to chat |
| 3 | Click "Continue Rating" button | Button shows "Continue" not "Start" |
| 4 | Grid loads with saved positions | Previously placed cards restored |
| 5 | Next proposition fetched | Can continue where left off |

### Test 9.3: Undo After Compression
**Scenario:** Undo restores positions correctly after compression

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Complete binary phase (A@100, B@0) | Two cards placed |
| 2 | Third prop (C) appears at 50 | Active card |
| 3 | Move C ABOVE 100 (past top) | A compresses down (e.g., to 70) |
| 4 | Press Undo (don't confirm C) | C removed |
| 5 | Verify A restored to 100, B at 0 | Uncompression works |
| 6 | Arrow keys work normally | No jumping |

### Test 9.4: Undo With Stacked Cards
**Scenario:** Multiple cards at same position spread after undo

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Resume with stacked cards (A@100, B@100, C@0) | From saved rankings |
| 2 | New prop D appears | Active |
| 3 | Move D past 100 | A and B compress together |
| 4 | Press Undo | D removed |
| 5 | Verify A and B are SPREAD apart | Not both at 100 |

### Test 9.5: Continue Rating Button
**Scenario:** Button text reflects partial progress

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Start rating with 0 rankings | Button shows "Start Rating" |
| 2 | Place some rankings, leave | Partial progress saved |
| 3 | Return to chat screen | Button shows "Continue Rating" |
| 4 | Complete all rankings | Button hidden, "Rating Complete" shown |

---

## Phase 10: Auto-Advance (Early Advance) Testing

### Test 10.1: Auto-Advance Proposing (Threshold Met)
**Scenario:** Phase advances early when participation thresholds are met

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto mode, 30 min proposing timer | - |
| 2 | Enable auto-advance proposing: 80%, min 3 participants | - |
| 3 | 5 participants join | - |
| 4 | 4 of 5 submit propositions (80%) | - |
| 5 | Verify phase advances immediately | Doesn't wait for timer |
| 6 | Check "advanced early" indicator | Shows early advance reason |

### Test 10.2: Auto-Advance Proposing (Threshold Not Met - Percent)
**Scenario:** Phase waits for timer when percent threshold not met

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto-advance: 80%, min 3 | - |
| 2 | 10 participants join | - |
| 3 | Only 5 submit (50%) | Below 80% |
| 4 | Verify phase does NOT advance early | Waits for timer |
| 5 | Timer expires | Phase advances normally |

### Test 10.3: Auto-Advance Proposing (Threshold Not Met - Count)
**Scenario:** Phase waits when min count threshold not met

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto-advance: 80%, min 5 | - |
| 2 | 3 participants join | Below min count |
| 3 | All 3 submit (100%) | Percent met, count not |
| 4 | Verify phase does NOT advance early | Both conditions required |

### Test 10.4: Auto-Advance Rating
**Scenario:** Rating phase advances early when all have rated

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto-advance rating: 100%, min 2 | - |
| 2 | 5 participants in rating phase | - |
| 3 | All 5 complete ratings | 100% participation |
| 4 | Verify phase advances immediately | Round completes early |

### Test 10.5: Auto-Advance Disabled
**Scenario:** No early advance when disabled

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto-advance DISABLED | Default off |
| 2 | All participants submit propositions | 100% participation |
| 3 | Verify phase does NOT advance early | Waits for timer |

---

## Phase 11: Minimum Participation Settings

### Test 11.1: Minimum Propositions Required
**Scenario:** Cannot advance without minimum propositions

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with proposing_minimum: 3 | - |
| 2 | Only 2 propositions submitted | Below minimum |
| 3 | Host tries to advance to rating | Error: "Need at least 3 propositions" |
| 4 | Submit third proposition | - |
| 5 | Host advances to rating | Success |

### Test 11.2: Minimum Ratings Required
**Scenario:** Cannot complete round without minimum ratings

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with rating_minimum: 3 | - |
| 2 | Only 2 participants rate | Below minimum |
| 3 | Timer expires or host advances | Warning about minimum |
| 4 | Third participant rates | - |
| 5 | Round completes | Winner calculated |

### Test 11.3: Default Minimums (2 each)
**Scenario:** Verify default behavior

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with default settings | proposing_min: 2, rating_min: 2 |
| 2 | Submit 1 proposition | Cannot advance |
| 3 | Submit second proposition | Can advance |
| 4 | 1 person rates | Cannot complete |
| 5 | Second person rates | Round completes |

---

## Phase 12: Adaptive Duration Testing

### Test 12.1: Adaptive Duration Increases Time
**Scenario:** Timer extends when participation is high

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with adaptive_duration: enabled | - |
| 2 | Set threshold_count: 5, adjustment_percent: 20 | - |
| 3 | Set base proposing duration: 5 minutes | 300 seconds |
| 4 | 10 participants join (above threshold) | - |
| 5 | Verify timer shows extended time | ~6 minutes (20% more) |

### Test 12.2: Adaptive Duration Decreases Time
**Scenario:** Timer shortens when participation is low

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with adaptive_duration: enabled | - |
| 2 | Set threshold_count: 10, adjustment_percent: 20 | - |
| 3 | Set base proposing duration: 10 minutes | - |
| 4 | Only 3 participants join (below threshold) | - |
| 5 | Verify timer shows reduced time | ~8 minutes (20% less) |

### Test 12.3: Adaptive Duration Respects Min/Max
**Scenario:** Duration stays within bounds

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with min_duration: 2 min, max_duration: 30 min | - |
| 2 | Set very high adjustment (50%) | - |
| 3 | With few participants | Duration doesn't go below 2 min |
| 4 | With many participants | Duration doesn't exceed 30 min |

### Test 12.4: Adaptive Duration Disabled
**Scenario:** Timer doesn't adjust when disabled

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with adaptive_duration: disabled | Default |
| 2 | Set proposing duration: 5 minutes | - |
| 3 | 20 participants join | - |
| 4 | Verify timer still shows 5 minutes | No adjustment |

---

## Phase 13: Email Invitations (Detailed)

### Test 13.1: Send Email Invitation
**Scenario:** Host invites user via email

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with access_method: "Invite Only" | - |
| 2 | Enter email: test@example.com | - |
| 3 | Tap "Send Invite" | Invitation sent |
| 4 | Check `invites` table | Row created with token |
| 5 | Check email delivery (or logs) | Email sent via Edge Function |

### Test 13.2: Join via Email Token
**Scenario:** Invited user joins using token link

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Get invite token from database | - |
| 2 | Open app with token URL: `/join?token=xxx` | - |
| 3 | Verify chat details shown | Chat name, topic visible |
| 4 | Enter display name and join | Joined successfully |
| 5 | Verify invite marked as used | `used_at` populated |

### Test 13.3: Expired Invitation
**Scenario:** Token expires after 7 days

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create invite, manually set expires_at to past | - |
| 2 | Try to join with expired token | Error: "Invitation expired" |
| 3 | Cannot join | Access denied |

### Test 13.4: Revoke Invitation
**Scenario:** Host cancels pending invite

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Send invitation to user | Pending invite exists |
| 2 | Host opens invite management | List of pending invites |
| 3 | Host revokes invitation | Invite deleted |
| 4 | User tries to use token | Error: "Invalid invitation" |

### Test 13.5: Resend Invitation
**Scenario:** Host resends to same email

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Send invitation to test@example.com | - |
| 2 | Send again to same email | New token generated |
| 3 | Old token invalidated | Previous invite revoked |
| 4 | New email sent | Fresh link works |

---

## Phase 14: Carry Forward Winners

### Test 14.1: Winner Carried to Next Round
**Scenario:** Winning proposition appears in next round

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Complete round 1 with winner "Idea A" | 1/2 consensus wins |
| 2 | Round 2 starts (proposing) | - |
| 3 | Verify "Idea A" shown as carried forward | Marked as previous winner |
| 4 | Users can submit new propositions | New ideas added |
| 5 | "Idea A" competes again | Can win consensus |

### Test 14.2: Tie Does Not Carry Forward
**Scenario:** Tied winners reset the chain

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Round 1: "Idea A" wins | 1/2 consensus |
| 2 | Round 2: Tie between A and B | Chain broken |
| 3 | Round 3 starts | NO carried forward winners |
| 4 | Fresh competition | All new propositions |

### Test 14.3: Carried Forward Cannot Be Deleted
**Scenario:** Previous winners are protected

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | "Idea A" carried forward to round 2 | - |
| 2 | Host views all propositions | - |
| 3 | Verify NO delete button on carried forward | Protected from deletion |
| 4 | Can delete new propositions | Only new ones deletable |

### Test 14.4: Multiple Rounds Carry Forward
**Scenario:** Winner persists through multiple rounds

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Round 1: "Idea A" wins | 1/2 |
| 2 | Round 2: "Idea A" wins again | Consensus reached! |
| 3 | New cycle starts | - |
| 4 | "Idea A" NOT carried (it's now consensus) | Fresh start |

---

## Phase 15: Advanced Consensus Settings

### Test 15.1: Show Previous Results Enabled
**Scenario:** Users see last round's winner during proposing

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with show_previous_results: true | - |
| 2 | Complete round 1 | Winner determined |
| 3 | Round 2 proposing starts | - |
| 4 | Verify "Previous Winner" section visible | Shows round 1 winner |
| 5 | All users can see it | Influences new proposals |

### Test 15.2: Show Previous Results Disabled
**Scenario:** Previous winner hidden during proposing

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with show_previous_results: false | Default |
| 2 | Complete round 1 | Winner determined |
| 3 | Round 2 proposing starts | - |
| 4 | Verify NO previous winner shown | Blind proposing |
| 5 | Previous winner only visible after rating | Revealed when needed |

### Test 15.3: Multiple Propositions Per User
**Scenario:** Users can submit 3 ideas each

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with propositions_per_user: 3 | - |
| 2 | User submits first idea | "1/3 submitted" |
| 3 | User submits second idea | "2/3 submitted" |
| 4 | User submits third idea | "3/3 submitted", input disabled |
| 5 | User cannot submit fourth | Limit enforced |

### Test 15.4: Single Proposition Per User (Default)
**Scenario:** Default one idea per user

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with propositions_per_user: 1 | Default |
| 2 | User submits idea | "Waiting for rating phase..." |
| 3 | Input field hidden | Cannot submit more |
| 4 | Counter NOT shown | No "1/1" display for single |

### Test 15.5: High Confirmation Rounds
**Scenario:** Requires 3 consecutive wins

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with confirmation_rounds_required: 3 | - |
| 2 | "Idea A" wins round 1 | "1/3 toward consensus" |
| 3 | "Idea A" wins round 2 | "2/3 toward consensus" |
| 4 | "Idea A" wins round 3 | Consensus reached! |

---

## Phase 16: Billing & Credits

### Test 16.1: View Credit Balance
**Scenario:** User sees their credit balance

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Log in with Google OAuth | Authenticated user |
| 2 | Navigate to billing/account | Credit balance shown |
| 3 | Verify free tier credits | 100 free credits visible |
| 4 | Verify balance displays correctly | Formatted as "X credits" |

### Test 16.2: Purchase Credits (Stripe Checkout)
**Scenario:** User buys credits via Stripe

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate to buy credits | Purchase options shown |
| 2 | Select 100 credits ($10) | - |
| 3 | Click "Purchase" | Redirected to Stripe Checkout |
| 4 | Complete test payment (4242...) | Payment succeeds |
| 5 | Redirected back to app | Credits added to balance |
| 6 | Check credit_transactions table | Transaction logged |

### Test 16.3: Credit Deduction (Host Chat)
**Scenario:** Credits deducted when hosting rounds

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Note starting credit balance | e.g., 100 credits |
| 2 | Create and host a chat | - |
| 3 | Complete a round with 5 participants | 5 user-rounds |
| 4 | Check credit balance | Reduced by 5 |
| 5 | Check transaction history | Deduction logged |

### Test 16.4: Insufficient Credits
**Scenario:** Cannot host without credits

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Reduce credits to 0 | - |
| 2 | Try to create/host a chat | Warning about credits |
| 3 | Try to start a round | Blocked or prompted to buy |

### Test 16.5: Transaction History
**Scenario:** User views credit history

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate to transaction history | - |
| 2 | Verify purchases shown | "Purchased 100 credits" |
| 3 | Verify deductions shown | "Hosted round: -5 credits" |
| 4 | Verify timestamps | Ordered by date |

---

## Phase 17: Auto-Refill

### Test 17.1: Setup Payment Method
**Scenario:** User saves card for auto-refill

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate to auto-refill settings | - |
| 2 | Click "Add Payment Method" | Stripe Elements form |
| 3 | Enter test card (4242...) | - |
| 4 | Submit | Card saved |
| 5 | Verify card last 4 digits shown | "•••• 4242" displayed |

### Test 17.2: Configure Auto-Refill
**Scenario:** Set threshold and refill amount

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Enable auto-refill | Toggle on |
| 2 | Set threshold: 10 credits | - |
| 3 | Set refill amount: 50 credits | - |
| 4 | Save settings | Confirmed |
| 5 | Verify settings in database | Values stored correctly |

### Test 17.3: Auto-Refill Triggers
**Scenario:** Credits auto-purchased when low

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Set balance to 15 credits | - |
| 2 | Set threshold: 10, amount: 50 | - |
| 3 | Host round that uses 10 credits | Balance drops to 5 |
| 4 | Verify auto-refill triggered | 50 credits added |
| 5 | Check Stripe for charge | Payment processed |
| 6 | New balance: 55 credits | 5 + 50 = 55 |

### Test 17.4: Auto-Refill Disabled
**Scenario:** No auto-purchase when disabled

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Disable auto-refill | Toggle off |
| 2 | Balance drops below threshold | - |
| 3 | Verify NO auto-purchase | Balance stays low |
| 4 | User must manually purchase | Prompted when needed |

### Test 17.5: Remove Payment Method
**Scenario:** User removes saved card

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate to payment settings | - |
| 2 | Click "Remove Payment Method" | Confirmation dialog |
| 3 | Confirm removal | Card removed |
| 4 | Auto-refill automatically disabled | Can't refill without card |

---

## Phase 18: Analytics & Monitoring

### Test 18.1: Screen View Tracking
**Scenario:** Firebase tracks screen views

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate through app screens | Home → Discover → Chat |
| 2 | Check Firebase console | Screen views logged |
| 3 | Verify screen names correct | "HomeScreen", "DiscoverScreen", etc. |

### Test 18.2: Event Tracking
**Scenario:** Key actions are tracked

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a chat | "chat_created" event |
| 2 | Join a chat | "chat_joined" event |
| 3 | Submit proposition | "proposition_submitted" event |
| 4 | Complete rating | "rating_completed" event |
| 5 | Check Firebase console | All events logged with params |

### Test 18.3: Error Tracking (Sentry)
**Scenario:** Errors reported to Sentry

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Trigger an error (network fail, etc.) | - |
| 2 | Check Sentry dashboard | Error captured |
| 3 | Verify stack trace | Full trace available |
| 4 | Verify user context | Session info attached |

---

## Phase 19: Host Manual Pause

### Test 19.1: Host Sees Pause Button
**Scenario:** Host can see pause control in app bar

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat as User A (host) | Chat created |
| 2 | Start proposing phase with timer (auto mode) | Timer counting down |
| 3 | Verify pause button (⏸️) visible in app bar | Icon button shown |
| 4 | As User B (non-host), join the chat | Joined as participant |
| 5 | Verify User B does NOT see pause button | No pause control for non-hosts |

### Test 19.2: Host Pauses Chat Mid-Phase
**Scenario:** Host pauses during active proposing phase

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto mode, 5 min proposing timer | Timer set |
| 2 | Start round, note timer (e.g., 4:30 remaining) | Timer visible |
| 3 | As host, tap pause button | Confirmation dialog appears |
| 4 | Confirm pause | Chat paused |
| 5 | Verify timer stops/disappears | No countdown shown |
| 6 | Verify pause button changes to play (▶️) | Resume button now visible |
| 7 | Verify database: `host_paused = true` | Flag set |
| 8 | Verify database: `phase_time_remaining_seconds ≈ 270` | ~4:30 saved |
| 9 | Verify database: `phase_ends_at = NULL` | Timer stopped |

### Test 19.3: Participants See Paused Banner
**Scenario:** Non-hosts see "Chat paused by host" message

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | With chat paused by host | - |
| 2 | As User B (participant), view chat | Chat screen loads |
| 3 | Verify orange banner visible | "Chat Paused by Host" banner |
| 4 | Verify banner message | "The host has paused this chat. Please wait for them to resume." |
| 5 | Verify participant can still see propositions | Content visible but phase frozen |

### Test 19.4: Host Sees Different Banner Message
**Scenario:** Host sees actionable message

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | With chat paused by host | - |
| 2 | As User A (host), view chat | Chat screen loads |
| 3 | Verify banner message is different | "The timer is stopped. Tap Resume in the app bar to continue." |

### Test 19.5: Host Resumes Chat
**Scenario:** Host resumes and timer restores

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | With chat paused (saved time ~4:30) | Timer frozen |
| 2 | As host, tap resume/play button | No confirmation needed |
| 3 | Verify timer resumes | Shows ~4:30 remaining |
| 4 | Verify banner disappears | No paused state shown |
| 5 | Verify database: `host_paused = false` | Flag cleared |
| 6 | Verify database: `phase_time_remaining_seconds = NULL` | Saved time cleared |
| 7 | Verify database: `phase_ends_at ≈ NOW() + 4:30` | Timer restored |

### Test 19.6: Double Pause is Idempotent
**Scenario:** Pausing twice doesn't corrupt state

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As host, pause chat | Paused |
| 2 | Call `host_pause_chat()` via SQL console | Already paused |
| 3 | Verify still paused, timer still saved | No state corruption |
| 4 | Resume chat | Resumed |
| 5 | Call `host_resume_chat()` via SQL console | Already resumed |
| 6 | Verify still running, timer active | No state corruption |

### Test 19.7: Schedule Pause + Host Pause Interaction
**Scenario:** Both pause types must be false for timer to run

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create recurring scheduled chat | Schedule windows set |
| 2 | Wait for schedule to pause chat (outside window) | `schedule_paused = true` |
| 3 | Verify `is_chat_paused()` returns true | Combined pause check |
| 4 | As host, manually pause chat | `host_paused = true` |
| 5 | Verify `is_chat_paused()` still returns true | Both pauses active |
| 6 | As host, resume chat (clear host_paused) | `host_paused = false` |
| 7 | Verify `is_chat_paused()` STILL returns true | Schedule still pausing |
| 8 | Verify timer NOT restored | `phase_ends_at` still NULL |
| 9 | Wait for schedule window to open | `schedule_paused = false` |
| 10 | Verify timer now restores | Both pauses false, timer runs |

### Test 19.8: Pause During Rating Phase
**Scenario:** Host can pause during rating phase too

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Advance to rating phase with timer | Timer counting |
| 2 | Some users have rated, some haven't | Partial ratings |
| 3 | As host, pause chat | Chat paused |
| 4 | Verify timer stops, rating progress preserved | Ratings saved |
| 5 | As host, resume chat | Timer restores |
| 6 | Users can continue rating | Rating phase continues |

### Test 19.9: Pause in Manual Mode (No Timer)
**Scenario:** Pause works even without active timer

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with manual mode (no timers) | No auto-advance |
| 2 | Start proposing phase | No timer displayed |
| 3 | As host, pause chat | Chat paused |
| 4 | Verify `host_paused = true` | Flag set |
| 5 | Verify banner shown | Paused state visible |
| 6 | As host, resume chat | Chat resumed |
| 7 | Verify proposing continues | Phase unchanged |

### Test 19.10: Non-Host Cannot Pause (API Level)
**Scenario:** RLS prevents non-hosts from calling pause functions

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As User B (non-host), try to call `host_pause_chat()` | - |
| 2 | Via SQL or API: `SELECT host_pause_chat(chat_id)` | - |
| 3 | Verify error: "Only hosts can pause the chat" | Permission denied |

### Test 19.11: Inputs Disabled When Paused (Proposing)
**Scenario:** Proposition text field and submit button disabled when paused

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Start proposing phase | Text field and Submit button enabled |
| 2 | As host, pause chat | Chat paused |
| 3 | As participant, verify text field is disabled | Cannot type |
| 4 | Verify hint text shows "Chat is paused..." | Paused placeholder |
| 5 | Verify Submit button is disabled (grayed out) | Cannot tap |
| 6 | As host, resume chat | Chat resumed |
| 7 | Verify text field and button re-enabled | Can submit again |

### Test 19.12: Inputs Disabled When Paused (Rating)
**Scenario:** Start Rating button disabled when paused

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Advance to rating phase | "Start Rating" button enabled |
| 2 | As host, pause chat | Chat paused |
| 3 | As participant who hasn't rated, view chat | - |
| 4 | Verify "Start Rating" button is disabled | Cannot tap |
| 5 | Verify text shows "Chat is paused..." | Paused message |
| 6 | As host, resume chat | Chat resumed |
| 7 | Verify "Start Rating" button re-enabled | Can start rating |

### Test 19.13: Kick From GridRankingScreen When Paused
**Scenario:** User in grid ranking screen is sent back when host pauses

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | As User B (participant), tap "Start Rating" | Grid ranking screen opens |
| 2 | Place 1-2 propositions (don't finish) | Partial progress |
| 3 | As User A (host), pause the chat | Chat paused |
| 4 | User B's grid ranking screen auto-closes | Popped back to chat |
| 5 | Snackbar shows "Chat was paused by host" | Notification visible |
| 6 | User B sees paused banner on chat screen | Paused state visible |
| 7 | As host, resume chat | Chat resumed |
| 8 | User B can tap "Continue Rating" | Progress preserved |

### Test 19.14: Resume Timer Aligns to Whole Minutes
**Scenario:** Timer resume aligns to :00 seconds for cron compatibility

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create chat with auto mode | Timer set |
| 2 | Start round, note the exact time (e.g., 12:02:33) | Timer running |
| 3 | Let timer run to ~3:30 remaining | Timer counting |
| 4 | As host, pause chat | Timer saved as ~210 seconds |
| 5 | Wait ~30 seconds (e.g., until 12:03:05) | - |
| 6 | As host, resume chat | Timer restored |
| 7 | Check database: `phase_ends_at` | Should end at :00 seconds |
| 8 | Example: If resumed at 12:03:05 + 210s = 12:06:35 | Rounds UP to 12:07:00 |
| 9 | Verify `EXTRACT(SECOND FROM phase_ends_at) = 0` | Aligned to minute |
| 10 | Verify timer countdown matches phase transition | No "0:00 but nothing happens" bug |

---

## Test Execution Checklist

### Before Testing
- [ ] Database reset (`npx supabase db reset`)
- [ ] All migrations applied
- [ ] No pre-existing test data

### Test Execution
- [ ] Phase 1: Basic Flow (Tests 1.1 - 1.7)
- [ ] Phase 2: Start Modes (Tests 2.1 - 2.3, 2.3b needs testing)
- [ ] Phase 3: Access Methods (Tests 3.1 - 3.3)
- [ ] Phase 4: Constraints (Tests 4.1 - 4.3)
- [ ] Phase 5: Host Powers (Tests 5.1 - 5.4)
- [ ] Phase 6: Consensus (Tests 6.1 - 6.3)
- [ ] Phase 7: Edge Cases (Tests 7.1 - 7.4)
- [ ] Phase 8: Multi-Use Case (Tests 8.1 - 8.4)
- [ ] Phase 9: Grid Ranking (Tests 9.1 - 9.5)
- [ ] Phase 10: Auto-Advance (Tests 10.1 - 10.5)
- [ ] Phase 11: Minimum Participation (Tests 11.1 - 11.3)
- [ ] Phase 12: Adaptive Duration (Tests 12.1 - 12.4)
- [ ] Phase 13: Email Invitations (Tests 13.1 - 13.5)
- [ ] Phase 14: Carry Forward Winners (Tests 14.1 - 14.4)
- [ ] Phase 15: Consensus Settings (Tests 15.1 - 15.5)
- [ ] Phase 16: Billing & Credits (Tests 16.1 - 16.5)
- [ ] Phase 17: Auto-Refill (Tests 17.1 - 17.5)
- [ ] Phase 18: Analytics & Monitoring (Tests 18.1 - 18.3)
- [ ] Phase 19: Host Manual Pause (Tests 19.1 - 19.14)

### After Testing
- [ ] Document any bugs found
- [ ] Note UX improvements needed
- [ ] Verify all critical paths work

---

## Bug Report Template

```
**Test:** [Test number]
**Severity:** Critical / High / Medium / Low
**Steps to Reproduce:**
1.
2.
3.

**Expected:**
**Actual:**
**Screenshots:** [if applicable]
**Device/Browser:**
```
