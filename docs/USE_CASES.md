# OneMind Use Cases

This document maps real-world scenarios to OneMind settings, helping users configure chats for their specific needs.

---

## Quick Reference

> For manual testing procedures that validate these use cases, see [TESTING_PLAN.md](./TESTING_PLAN.md) Phase 8.

| Use Case | Access | Start Mode | Timers | Min Participants | Confirmation |
|----------|--------|------------|--------|------------------|--------------|
| Official OneMind | Public | Auto | 1 day | 3+ | 2 |
| Community Forum | Public | Manual | None | 3+ | 2 |
| Team Decision | Code | Auto | 1 hour | 3+ | 2 |
| Quick Poll | Code | Manual | None | 3+ | 1 |
| Board Meeting | Email + Auth | Scheduled | 30 min | 3+ | 2 |
| Classroom | Code | Auto (20) | 15 min | 20+ | 1 |
| Brainstorming | Code | Manual | None | 3+ | 1 |
| Family Decision | Code | Manual | None | 3+ | 1 |
| Conference Q&A | Public | Manual | None | 10+ | 1 |
| Research Panel | Email + Auth | Manual | None | 5+ | 3 |

**Notes:**
- All use cases require minimum 3 participants for rating to work (each proposition needs 2+ raters, and users can't rate their own).

---

## 1. Official OneMind Chat

**Scenario:** Humanity's always-on public square. The default landing experience where anyone can participate in ongoing global discussions.

**Example Question:** "What should humanity prioritize this decade?"

| Setting | Value | Reason |
|---------|-------|--------|
| `is_official` | TRUE | Special status, always visible |
| `access_method` | public | Open to everyone |
| `require_auth` | FALSE | Maximum participation |
| `require_approval` | FALSE | No barriers |
| `start_mode` | auto | Auto-start when enough participants |
| `auto_start_participant_count` | 10 | Begin when 10 people join |
| `proposing_duration` | 1 day | Time for thoughtful proposals |
| `rating_duration` | 1 day | Global participation across timezones |
| `confirmation_rounds` | 2 | Ensure consensus, not fluke |
| `propositions_per_user` | 1 | Focus on quality |
| `enable_ai` | TRUE | AI contributes perspectives |
| `show_previous_results` | FALSE | Fresh perspective each round |

---

## 2. Community Forum / Open Discussion

**Scenario:** A public chat about a shared interest (book club, hobby group, local community).

**Example Question:** "What book should our club read next?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | public | Discoverable, open community |
| `require_auth` | FALSE | Easy to join |
| `require_approval` | FALSE | Instant participation |
| `proposing_duration` | 1 day | Give members time |
| `rating_duration` | 1 day | Async-friendly |
| `confirmation_rounds` | 2 | Confirm the choice |
| `propositions_per_user` | 1 | One suggestion per person |
| `start_mode` | manual | Host controls when to begin |

**Discovery:** Users find it in Discover screen by searching "book club" or similar.

---

## 3. Team Decision Making

**Scenario:** A work team choosing between options (sprint priorities, project names, lunch spots).

**Example Question:** "Which feature should we build next quarter?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | code | Private to team |
| `require_auth` | FALSE or TRUE | Optional accountability |
| `require_approval` | FALSE | Trust the team |
| `proposing_duration` | 1 hour | Focused session |
| `rating_duration` | 1 hour | Quick turnaround |
| `confirmation_rounds` | 2 | Ensure real consensus |
| `propositions_per_user` | 1 | One vote per person |
| `auto_advance` | 80% threshold | Move when most have participated |

**Sharing:** Host shares code "A7X3K9" in Slack or meeting chat.

---

## 4. Quick Poll Among Friends

**Scenario:** Fast decision with a small group (where to eat, what movie to watch).

**Example Question:** "Where should we go for dinner tonight?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | code | Share in group chat |
| `require_auth` | FALSE | No friction |
| `require_approval` | FALSE | Instant join |
| `proposing_duration` | 5 min | Quick! |
| `rating_duration` | 5 min | Quick! |
| `confirmation_rounds` | 1 | First winner wins |
| `propositions_per_user` | 1 | One suggestion each |
| `proposing_minimum` | 2 | Need at least 2 options |
| `rating_minimum` | 2 | At least 2 people rate |

**Use Case:** "Hey everyone, join A7X3K9 and suggest dinner spots!"

---

## 5. Board / Committee Meeting

**Scenario:** Formal decision-making body with known members, scheduled meetings.

**Example Question:** "Should we approve the Q3 budget proposal?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | invite_only | Only board members |
| `require_auth` | TRUE | Verify identity |
| `require_approval` | FALSE | Pre-approved via email |
| `start_mode` | scheduled | Meeting at set time |
| `schedule_type` | recurring | Weekly board meeting |
| `schedule_timezone` | America/New_York | Auto-detected, can override |
| `schedule_windows` | See below | Tuesday 2-3 PM window |
| `proposing_duration` | 30 min | Half for proposals |
| `rating_duration` | 30 min | Half for voting |
| `confirmation_rounds` | 2 | Require confirmation |
| `propositions_per_user` | 1 | Formal motions |

**Schedule Window:**
```json
[{"start_day": "tuesday", "start_time": "14:00", "end_day": "tuesday", "end_time": "15:00"}]
```

**Invitations:** Host adds board members by email before the meeting.

---

## 6. Classroom / Workshop

**Scenario:** Teacher or facilitator leading a group exercise with students.

**Example Question:** "What are possible solutions to climate change?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | code | Share code on screen |
| `require_auth` | FALSE | Students join easily |
| `require_approval` | FALSE | Quick class start |
| `start_mode` | auto | Start when 20 students join |
| `auto_start_count` | 20 | Class size |
| `proposing_duration` | 15 min | Brainstorm time |
| `rating_duration` | 10 min | Quick evaluation |
| `confirmation_rounds` | 1 | Single round exercise |
| `propositions_per_user` | 3 | Multiple ideas per student |
| `show_previous_results` | TRUE | Learning from all ideas |

**Flow:** Teacher displays code, students join on phones, ideas flow in anonymously.

---

## 7. Brainstorming Session

**Scenario:** Creative team generating many ideas quickly, quantity over quality initially.

**Example Question:** "What should we name our new product?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | code | Team access |
| `require_auth` | FALSE | Focus on ideas, not identity |
| `proposing_duration` | 10 min | Rapid fire |
| `rating_duration` | 10 min | Quick evaluation |
| `confirmation_rounds` | 1 | First pass filter |
| `propositions_per_user` | 10 | Many ideas! |
| `proposing_minimum` | 5 | Want lots of options |
| `enable_ai` | TRUE | AI adds creative options |
| `ai_propositions_count` | 5 | AI contributes too |

**Purpose:** Generate maximum ideas, let the group filter naturally.

---

## 8. Family Decision

**Scenario:** Family choosing together (vacation destination, pet name, what to do this weekend).

**Example Question:** "Where should we go for summer vacation?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | code | Share with family |
| `require_auth` | FALSE | Kids can join easily |
| `require_approval` | FALSE | It's family |
| `proposing_duration` | 1 day | Everyone thinks |
| `rating_duration` | 1 day | Flexible timing |
| `confirmation_rounds` | 1 | Simple decision |
| `propositions_per_user` | 1 | One idea each |

**Sharing:** Parent texts code to family group chat.

---

## 9. Conference Session / Live Event

**Scenario:** Speaker collecting audience input during a talk or panel.

**Example Question:** "What topic should we discuss in the Q&A?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | public | Audience discovers easily |
| `require_auth` | FALSE | No friction |
| `require_approval` | FALSE | Real-time participation |
| `proposing_duration` | 30 min | During the talk |
| `rating_duration` | 15 min | Quick vote |
| `confirmation_rounds` | 1 | Time-limited event |
| `propositions_per_user` | 1 | One question per person |
| `proposing_threshold_count` | 10 | Move fast when enough input |

**Display:** QR code on screen links to the chat.

---

## 10. Research Panel / Delphi Study

**Scenario:** Controlled study with expert panelists, multiple rounds of refinement.

**Example Question:** "What are the key risks of AGI in the next decade?"

| Setting | Value | Reason |
|---------|-------|--------|
| `access_method` | invite_only | Curated experts |
| `require_auth` | TRUE | Verify expert identity |
| `require_approval` | TRUE | Double verification |
| `proposing_duration` | 1 day | Thoughtful input |
| `rating_duration` | 1 day | Careful evaluation |
| `confirmation_rounds` | 3 | Rigorous consensus |
| `propositions_per_user` | 1 | Focused expertise |
| `show_previous_results` | TRUE | Learn from each round |

**Method:** Multiple cycles until strong consensus emerges.

---

## Settings Impact Summary

### Access Method
- **Public:** Maximum reach, discoverable, good for communities and events
- **Code:** Private but easy to share, good for teams and groups
- **Email Invite:** Maximum control, good for formal/verified groups

### Timers
- **5-15 min:** Live sessions, quick decisions
- **1 hour:** Focused meetings, synchronous work
- **1 day:** Async participation, global/distributed teams
- **7 days:** Long-running discussions, deep deliberation

### Confirmation Rounds
- **1:** Quick decisions, polls, single-round exercises
- **2:** Standard consensus, filters out flukes (default)
- **3+:** High-stakes decisions, research, formal processes

### Propositions Per User
- **1:** Focus, equality, formal decisions
- **3-5:** Moderate brainstorming, classrooms
- **10+:** Maximum creativity, idea generation

### Authentication
- **Off:** Maximum participation, anonymity preserved
- **On:** Accountability, identity verification, multi-device access

---

## Anti-Patterns (What NOT to Do)

| Mistake | Problem | Fix |
|---------|---------|-----|
| Public + Require Approval | Host overwhelmed with requests | Use code instead, or remove approval |
| 5 min timer + 3 confirmation rounds | Takes 30+ min minimum | Reduce rounds or increase timers |
| Email invite + No auth | Can't verify identity | Enable require_auth |
| 10 props/user + 1 min timer | Not enough time | Increase timer or reduce props |
| Only 2 participants | Can't reach `rating_minimum = 2` | Need at least 3 participants |
| `rating_minimum` > participants - 1 | Impossible to complete rating | Ensure enough participants for your settings |
| Manual mode expecting timers | No timers in manual mode | Use auto/scheduled if you want timers |

---

## Start Mode Guide

### Manual Mode (Host Controls Everything)
Best for: Live events, meetings, classrooms, any scenario where a facilitator is present.

| Behavior | Description |
|----------|-------------|
| First round | Host clicks "Start Phase" to begin |
| Timers | **None** - no countdown displayed |
| Phase advancement | Host clicks to advance each phase |
| Proposing → Rating | Host clicks "End Proposing & Start Rating" |
| Rating → Next Round | Host clicks "End Rating" |

**When to use:**
- You're actively facilitating
- Participant availability is unpredictable
- You want full control over pacing

### Auto Mode (Timer-Based Automation)
Best for: Async teams, communities, ongoing discussions.

| Behavior | Description |
|----------|-------------|
| First round | Starts when `auto_start_participant_count` reached |
| Timers | Active countdown displayed |
| Phase advancement | Timer auto-advances OR host can advance early |
| Early advance | Available via threshold settings or manual override |

**When to use:**
- Participants join asynchronously
- You want the chat to run on autopilot
- You want deadlines but host can override if needed

### Scheduled Mode (Calendar-Based)
Best for: Recurring meetings, board sessions, weekly standups.

| Behavior | Description |
|----------|-------------|
| First round | Starts at scheduled time |
| Schedule types | One-time (`once`) or recurring (`recurring`) |
| Timers | Active countdown displayed after start |
| Phase advancement | Timer auto-advances OR host can advance early |

**When to use:**
- Regular meeting cadence
- Participants expect specific times
- Want automation but on a schedule

---

## Participant Requirements

### Minimum Participants
OneMind requires **at least 3 participants** for a chat to function fully:

| Phase | Requirement | Reason |
|-------|-------------|--------|
| Proposing | 2+ propositions | Need 2+ options to compare |
| Rating | 3+ participants | Each proposition needs 2+ raters, and you can't rate your own |

### The Math
- `rating_minimum = 2` means each proposition needs 2 different people to rate it
- Since users can't rate their own proposition, with N participants each proposition can get at most N-1 ratings
- Therefore: N-1 >= 2, so N >= 3

### Examples

| Participants | Propositions | Max Ratings/Prop | Can Complete? |
|--------------|--------------|------------------|---------------|
| 2 | 2 | 1 | No (need 2) |
| 3 | 3 | 2 | Yes |
| 5 | 5 | 4 | Yes |
| 10 | 10 | 9 | Yes |

### Why Rating Auto-Advance Has No Percent Threshold

The UI only offers a count threshold for rating auto-advance (not a percent slider like proposing).

**Reason:** With small groups, percent thresholds can be mathematically impossible:
- 3 participants, 80% threshold → need 2.4 avg raters/prop
- But max possible is 2 (since you can't rate your own)
- 80% is unreachable!

The count threshold (e.g., "at least 2 avg raters per prop") is clearer and always achievable.

---

## Preset Templates (Future Feature)

Potential quick-start templates:
- "Quick Poll" - Manual, 1 round, code access
- "Team Decision" - Auto, 1 hour timers, 2 rounds, code access
- "Community Discussion" - Auto, 1 day timers, 2 rounds, public
- "Formal Meeting" - Scheduled, email invite, auth required
- "Brainstorm" - Manual, 1 round, 10 props/user
