# OneMind Design Document

## Vision

**OneMind is a collective alignment platform for humanity.** It enhances cooperation through shared direction via a convergence mechanism.

### Core Principle

**Highly generic. Non-specific. Highly customizable.**

The same architecture powers both:
- **The Official OneMind Chat** - humanity's public square, always available
- **Private Chats** - created by anyone for any purpose

---

## Three Types of Chats

| Type | Access | Purpose |
|------|--------|---------|
| **Official OneMind** | Always visible, `is_official = TRUE` | Humanity's public square |
| **Public Chats** | Discoverable via Discover screen | Open communities, no code needed |
| **Private Chats** | Invite code or email invite required | Any group, any purpose |

---

## Design Decisions

| Decision | Choice |
|----------|--------|
| **Access** | 6-char invite code + shareable link `/join/CODE` |
| **Identity** | Anonymous by default, optional auth (Google OAuth + Magic Link) |
| **Auth data stored** | email, display_name, avatar_url |
| **Access method** | `public` (discoverable), `code` (6-char invite code), or `invite_only` (email token) |
| **Auth requirement** | `require_auth` boolean (works with any access method) |
| **Approval** | `require_approval` boolean (works with any combination) |
| **Host powers** | Approve joins, kick users, delete propositions, advance phases, end chat |
| **Host limits** | Cannot override winners, cannot see who proposed what |
| **Proposition anonymity** | Full - nobody sees who proposed (not host, not participants) |
| **Phase advancement** | Manual by host: proposing → rating → resolved (auto-calculates winner) |
| **Anonymous persistence** | localStorage session_token (survives browser close) |
| **Anonymous chat expiry** | 7 days after last activity |
| **Authenticated chat expiry** | Never (until manually deleted) |
| **Rate limit** | 10 active chats per anonymous session |
| **Max participants** | No limit |
| **Session tokens** | Client-generated UUID, server-validated |
| **Auth provider** | Supabase Auth (Google OAuth + Magic Link) |

---

## Access Model

### Public Chats
- Appear in Discover screen (searchable)
- No invite code required
- Anyone can join with one tap
- Creator can share via QR code or link

### Invite Code (for private chats)
- 6 characters: `A7X3K9`
- Character set: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no I/1, O/0 confusion)
- Auto-generated on chat creation
- ~1.07 billion combinations

### Three Ways to Join
| Method | Example | Use Case |
|--------|---------|----------|
| Discover | Browse public chats | Open communities |
| Code | `A7X3K9` | Verbal, text message |
| Link | `/join/A7X3K9` | Email, clickable |

---

## Identity Model

### Anonymous Users
- No sign-up required
- Enter display name → join instantly
- Session token stored in localStorage
- Same browser = same identity (persists across browser close)
- Different browser/device = new identity

### Authenticated Users
- Sign in via Google OAuth or Magic Link (email)
- No passwords
- Benefits: multi-device access, chat history, no expiration, no rate limit

---

## Join Settings Combinations

| access_method | require_auth | require_approval | Result |
|---------------|--------------|------------------|--------|
| `public` | OFF | OFF | Anyone discovers and joins instantly |
| `public` | OFF | ON | Anyone discovers and requests, host approves |
| `public` | ON | OFF | Signed-in users discover and join instantly |
| `public` | ON | ON | Signed-in users discover and request, host approves |
| `code` | OFF | OFF | Anyone with code joins instantly |
| `code` | OFF | ON | Anyone with code requests, host approves |
| `code` | ON | OFF | Signed-in users with code join instantly |
| `code` | ON | ON | Signed-in users with code request, host approves |
| `invite_only` | OFF | OFF | Email invitees join via token, anon OK |
| `invite_only` | OFF | ON | Email invitees request, host approves, anon OK |
| `invite_only` | ON | OFF | Email invitees must sign in with that email |
| `invite_only` | ON | ON | Email invitees sign in + host approves |

---

## Round Phases

```
proposing → rating → (winner set) → next round starts
```

| Phase | What happens |
|-------|--------------|
| `proposing` | Participants submit propositions |
| `rating` | Participants rank propositions via grid ranking |

**Only 2 phases.** When rating ends and winner is calculated:
- **Not N-in-a-row:** New round auto-created (same cycle, starts in `proposing`)
- **N-in-a-row achieved:** Cycle winner set → New cycle + first round auto-created

Where N = `confirmation_rounds_required` (configurable, default 2)

---

## Terminology

| Concept | Term |
|---------|------|
| The action | **Rate** |
| The stored value | **Rating** (converted from grid position) |
| The phase | **Rating phase** |
| The person | **Rater** |
| Series of rounds until N-in-a-row | **Cycle** |
| One propose → rate → winner | **Round** |
| Permanent winner (N-in-a-row) | **Consensus** |
| Temporary winner (bar to beat) | **Previous Winner** |
| How many wins needed | **Confirmation Rounds** |

---

## Start Mode

Controls how the chat begins AND how phases advance.

### Start Mode Options

| Mode | First Round Starts | Phase Timers | Phase Advancement |
|------|-------------------|--------------|-------------------|
| `manual` (default) | Host clicks "Start Phase" | **None** | Host clicks to advance each phase |
| `auto` | When `auto_start_participant_count` reached | Active | Timer auto-advances OR host can advance early |
| `scheduled` | At scheduled time | Active | Timer auto-advances OR host can advance early |

### Manual Mode (Full Host Control)
- **No timers displayed** - host decides when each phase ends
- **Host must click** to advance: waiting → proposing → rating → next round
- Best for: live events, meetings, classrooms where host is actively facilitating

### Auto Mode
- First round starts automatically when participant threshold reached
- Timers control phase transitions
- Host can still advance early if desired
- Best for: async groups, communities that run on autopilot

### Scheduled Mode
- First round starts at scheduled time (one-time or recurring)
- Timers control phase transitions after start
- Host can still advance early if desired
- Best for: recurring meetings, board sessions, weekly standups
- Supports flexible schedule windows (e.g., Mon 9am - Wed 5pm)
- Auto-detects user timezone on chat creation

**UI Behavior:**
- Before scheduled time: Shows "Scheduled to start" panel with date/time (local timezone)
- Recurring outside window: Shows "Chat is outside schedule window" panel
- Times displayed in user's local timezone (converted from UTC)
- UI auto-updates when scheduled time arrives (no manual refresh needed)

---

## Phase Advancement Settings

### Minimum to Advance (Hard Requirements)
Minimum required to advance. These are enforced for both timer-based and manual advancement.

| Setting | Default | Min | Description |
|---------|---------|-----|-------------|
| `proposing_minimum` | 2 | **2** | Minimum propositions needed (need 2+ to compare) |
| `rating_minimum` | 2 | **2** | Minimum avg raters per proposition (need 2+ for alignment) |

**Why minimum of 2?**
- `proposing_minimum >= 2`: You need at least 2 propositions to have something to compare/rate
- `rating_minimum >= 2`: Alignment requires multiple perspectives - 1 rater is just one opinion

**Participant Requirement:**
- Users cannot rate their own propositions
- With `rating_minimum = 2`, you need **at least 3 participants** for rating to complete
- Example: 3 people, each submits 1 proposition, each rates the other 2 → each proposition gets 2 ratings ✓

### Auto-Advance At (Take Profit)
Advance immediately when BOTH thresholds met.

| Setting | Default | Description |
|---------|---------|-------------|
| `proposing_threshold_percent` | OFF | % of participants who must propose |
| `proposing_threshold_count` | 5 | Minimum participants who must propose |
| `rating_threshold_percent` | OFF | % of participants who must rate |
| `rating_threshold_count` | 5 | Minimum participants who must rate |

**Logic: MAX of the two (both must be met)**

### Timer Settings
| Setting | Default | Minimum |
|---------|---------|---------|
| `proposing_duration_seconds` | 86400 (1 day) | 60 (1 min) |
| `rating_duration_seconds` | 86400 (1 day) | 60 (1 min) |

Timer presets: 5 min, 30 min, 1 hour, 1 day (max)

**Note:** Timers are only active for `auto` and `scheduled` start modes. In `manual` mode:
- No timers are displayed
- `phase_ends_at` is not set in the database
- Host must manually advance each phase

### Adaptive Duration (Optional)
Automatically adjust phase timers based on participation patterns.

| Setting | Default | Description |
|---------|---------|-------------|
| `adaptive_duration_enabled` | FALSE | Enable adaptive timing |
| `adaptive_threshold_count` | 10 | Participants before adaptation triggers |
| `adaptive_adjustment_percent` | 10 | Max % to adjust duration |
| `min_phase_duration_seconds` | 60 | Floor for duration |
| `max_phase_duration_seconds` | 86400 | Ceiling for duration |

---

## Scheduled Chats

Chats can be scheduled to start at specific times.

### Schedule Types
| Type | Description |
|------|-------------|
| `once` | One-time scheduled start at specific datetime |
| `recurring` | Repeats within flexible time windows (can span days) |

### Schedule Settings
| Setting | Description |
|---------|-------------|
| `schedule_type` | 'once' or 'recurring' |
| `schedule_timezone` | Timezone for schedule (auto-detected, user can override) |
| `scheduled_start_at` | For one-time: exact start datetime |
| `schedule_windows` | For recurring: JSONB array of time windows |
| `visible_outside_schedule` | Show chat outside active hours (default: TRUE) |

### Schedule Windows Format
Recurring schedules use flexible windows that can span multiple days:

```json
[
  {
    "start_day": "monday",
    "start_time": "09:00",
    "end_day": "monday",
    "end_time": "17:00"
  },
  {
    "start_day": "wednesday",
    "start_time": "14:00",
    "end_day": "friday",
    "end_time": "12:00"
  }
]
```

**Window types supported:**
- Same-day: Mon 9am → Mon 5pm
- Overnight: Fri 10pm → Sat 2am
- Multi-day: Wed 2pm → Fri 12pm

### Timezone Auto-Detection
When creating a chat, the user's timezone is automatically detected from their device.

**Supported timezones:**
- America/New_York, America/Chicago, America/Denver, America/Los_Angeles
- Europe/London, Europe/Paris
- Asia/Tokyo
- UTC

If the device timezone isn't in the supported list, it maps to the closest match by UTC offset.

---

## Consensus Settings

### Confirmation Rounds Required

| Setting | Default | Range | Description |
|---------|---------|-------|-------------|
| `confirmation_rounds_required` | 2 | 1-10 | How many consecutive wins needed for consensus |

**Examples:**
- `1` = First round winner wins immediately (no confirmation needed)
- `2` = Same proposition must win 2 rounds in a row (default)
- `3` = Same proposition must win 3 rounds in a row

### Tie Handling

When propositions have equal MOVDA scores (within 0.001 tolerance):

| Scenario | Behavior |
|----------|----------|
| A wins (sole), A wins (sole) | Consensus (2 sole wins) |
| A wins (sole), A+B tie | **NO consensus** (only 1 sole win, tie breaks chain) |
| A+B tie, A wins (sole) | **NO consensus** (tie broke chain, only 1 sole win after) |
| A+B tie, A+B tie | Continue (ties never count toward consensus) |

**Key points:**
- All tied winners are stored in `round_winners` table
- Only **sole wins** count toward consecutive win tracking
- Ties break the consecutive win chain
- UI shows all tied winners with navigation arrows

### Show Previous Results

| Setting | Default | Description |
|---------|---------|-------------|
| `show_previous_results` | FALSE | Whether to show full results or just winner |

When `show_previous_results = FALSE` (default):
- Users only see the winning proposition from previous rounds
- Full ratings and rankings are hidden

When `show_previous_results = TRUE`:
- Users see all propositions with their final ratings
- Rankings visible for all propositions

---

## Proposition Limits

| Setting | Default | Range | Description |
|---------|---------|-------|-------------|
| `propositions_per_user` | 1 | 1-20 | How many propositions each user can submit per round |

**Examples:**
- `1` = Each user can submit one proposition per round (default, forces focus)
- `3` = Each user can submit up to 3 propositions per round
- `10` = Brainstorming mode with many ideas per person

---

## OneMind AI (Optional)

An optional AI participant powered by Google Gemini.

| Setting | Default | Description |
|---------|---------|-------------|
| `enable_ai_participant` | FALSE | Enable/disable OneMind AI |
| `ai_propositions_count` | 3 | Propositions AI submits per phase |

### AI Behavior
- **Proposing phase:** Submits `ai_propositions_count` propositions
- **Rating phase:** Rates all propositions
- **Counts toward minimums:** Yes
- **Host can kick:** No (only disable the feature)

---

## Database Schema

### Tables

#### `chats`
```sql
id, name, initial_message, description, invite_code,
access_method, require_auth, require_approval,
creator_id, creator_session_token,
is_active, is_official, expires_at, last_activity_at,
start_mode, auto_start_participant_count,
proposing_duration_seconds, rating_duration_seconds,
proposing_minimum, rating_minimum,
proposing_threshold_percent, proposing_threshold_count,
rating_threshold_percent, rating_threshold_count,
enable_ai_participant, ai_propositions_count,
confirmation_rounds_required,  -- 1-10, default 2
show_previous_results,         -- default FALSE
propositions_per_user,         -- 1-20, default 1
created_at
```

#### `participants`
```sql
id, chat_id, user_id, session_token,
display_name, is_host, is_authenticated,
status ('pending', 'active', 'kicked', 'left'),
created_at
```

#### `cycles`
```sql
id, chat_id, winning_proposition_id,
created_at, completed_at
```

#### `rounds`
```sql
id, cycle_id, custom_id (round number),
phase ('waiting', 'proposing', 'rating'),
phase_started_at, phase_ends_at,
winning_proposition_id,
created_at, completed_at
```

#### `propositions`
```sql
id, round_id, participant_id,
content, created_at
```

#### `ratings`
```sql
id, proposition_id, participant_id,
rating, created_at  -- rating converted from grid position by MOVDA
```

#### `proposition_ratings` (computed)
```sql
proposition_id, rating (final avg), rank
```

### Key Triggers
- `on_chat_insert_set_code` - auto-generate invite code
- `on_chat_insert_set_expiration` - set 7-day expiry for anon chats
- `on_chat_check_limit` - enforce 10 chat limit for anon
- `on_proposition_update_activity` - reset expiry timer
- `on_rating_update_activity` - reset expiry timer
- `on_round_winner_set` - check N-in-a-row (configurable), create next round or new cycle
- `on_cycle_winner_set` - auto-create new cycle + first round
- `trg_proposition_limit` - enforce propositions_per_user limit

---

## UI Specification

### App Structure
| Element | Description |
|---------|-------------|
| Default view | Official OneMind chat at `/` |
| Navigation | Collapsible sidebar |
| Theme | System default (follows device) |

### Responsive Design
| Platform | Sidebar behavior |
|----------|------------------|
| Desktop | Collapsible, visible by default |
| Tablet | Collapsible, hidden by default |
| Mobile | Hamburger menu, slides in as overlay |

### Sidebar Contents
- Official OneMind (pinned at top)
- Your chats list (name, phase badge, action needed indicator)
- "+ Join Chat" button
- "+ Create Chat" button
- Pending chats (with "Pending" badge)

### Chat Room Layout
```
┌─────────────────────────────────┐
│ Header: Chat name, phase badge, │
│ timer, participant count        │
├─────────────────────────────────┤
│ Chat History                    │
│ - Initial Message (topic)       │
│ - Consensus #1, #2, ...         │
├─────────────────────────────────┤
│ Toggle Area                     │
│ Left: Previous Winner           │
│ Right: Input / Action / Leader  │
└─────────────────────────────────┘
```

### Host Powers
**Can Do:**
- Approve/deny join requests
- Kick users
- Delete propositions
- Advance phases
- End chat

**Cannot Do:**
- Override winners
- See who proposed what

---

## Error States

| Error | Message |
|-------|---------|
| Invalid code | "Chat not found" |
| Expired chat | "This chat has expired" |
| Ended chat | "This chat has ended" |
| Kicked | "You've been removed from this chat" |
| Auth required | "Sign in required to join" |
| Rate limit | "Limit reached (10 active chats)" |
| Network error | "Connection lost. Reconnecting..." |

---

## Expiration Rules

| Creator Type | Expiration |
|--------------|------------|
| Anonymous | 7 days after last activity |
| Authenticated | Never (until manually deleted) |

**Activity that resets timer:** New proposition or rating submitted

---

## Rate Limiting

| Rule | Limit |
|------|-------|
| Anonymous chats | 10 active per session_token |
| Authenticated chats | Unlimited |
| Max participants | No limit |
