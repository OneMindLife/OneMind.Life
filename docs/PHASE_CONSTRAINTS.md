# Phase Constraints & Minimum Settings

This document explains how the various numeric constraints work together to ensure the consensus algorithm functions correctly.

---

## Overview

The OneMind consensus process has interdependent constraints. Understanding these relationships is critical when modifying settings.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   WAITING   │ --> │  PROPOSING  │ --> │   RATING    │ --> [Winner Selected]
└─────────────┘     └─────────────┘     └─────────────┘
      │                    │                   │
      │                    │                   │
   Need N users      Need 3+ props      Need 2+ avg ratings
   (auto-start)      (to compare)       (for MOVDA algorithm)
```

---

## Key Constraints

### 1. `auto_start_participant_count` (minimum: 3)

**Why 3?** Users cannot rate their own propositions. With only 2 users:
- Each submits 1 proposition (2 total)
- Each user sees only 1 proposition (excluding their own)
- Grid ranking requires 2+ propositions to compare
- **Result:** Rating phase fails

**Formula:** `N - 1 >= 2` → `N >= 3`

---

### 2. `proposing_minimum` (minimum: 3)

**Why 3?** Same reasoning as above. Even if you have 10 users, you need at least 3 propositions so each user sees 2+ to rank.

**Edge case - Carry Forward:**
- Round 2+: Previous winner is carried forward
- 3 users + 1 carried = 4 propositions
- Each user sees 3 (own excluded, carried included if not original author)
- **Works correctly** ✓

---

### 3. `rating_minimum` (minimum: 2)

**Why 2 average ratings per proposition?**

The MOVDA (Margin of Victory Diminishing Adjustments) algorithm requires **pairwise comparisons**:

1. **Single rater = no comparisons** - Can't determine relative strength
2. **Two raters minimum** - Can compare how User A ranked X vs Y against how User B ranked X vs Y
3. **More raters = higher confidence** - Reduces volatility in scores

**Math with 3 users, 3 propositions:**
```
Each user rates: 3 - 1 = 2 propositions (excludes own)
Total ratings: 3 users × 2 = 6 ratings
Average per proposition: 6 / 3 = 2 ✓
```

**Math with 3 users + 1 carried (4 propositions):**
```
- Carried prop: 3 ratings (all can rate, unless original author)
- User A's prop: 2 ratings (B and C)
- User B's prop: 2 ratings (A and C)
- User C's prop: 2 ratings (A and B)
- Total: 3 + 2 + 2 + 2 = 9 ratings
- Average: 9 / 4 = 2.25 ✓
```

**What happens if minimum not met?** Timer extends (doesn't advance). See `process-timers/index.ts`.

---

### 4. `propositions_per_user` (minimum: 1)

**Interaction with other constraints:**

If `propositions_per_user = 2` with 3 users:
- 3 × 2 = 6 propositions total
- Each user sees 4 (excludes own 2)
- Still works ✓

**Warning:** High values with few users can create odd dynamics.

---

### 5. `confirmation_rounds_required` (range: 1-2)

**Why max 2?**
- Higher values make consensus nearly impossible
- With ties possible, requiring 3+ consecutive sole wins is very rare
- Practical limit keeps games finishable

---

### 6. Auto-Advance Thresholds

**`proposing_threshold_percent`** and **`proposing_threshold_count`**

Uses **MAX logic** (more restrictive wins):
```
required = MAX(
  ceil(participants × threshold_percent / 100),
  threshold_count
)
```

**Minimums enforced:**
- `proposing_threshold_count >= 3` (matches proposing_minimum)
- `rating_threshold_count >= 2` (matches rating_minimum reasoning)

---

## Original Author & Carried Propositions

**Rule:** Users cannot rate propositions they originally authored.

**Implementation:**
- `get_unranked_propositions()` excludes by `user_id` (not just `participant_id`)
- For carried propositions, traces `carried_from_id` chain to find original author
- Prevents gaming by leaving/rejoining to rate own carried proposition

**See:** `supabase/migrations/20260114000000_exclude_original_author_from_carried.sql`

---

## Constraint Relationship Diagram

```
auto_start_participant_count >= 3
         │
         ▼
    [N users join]
         │
         ▼
proposing_minimum >= 3  ←── Ensures each user sees 2+ props to compare
         │
         ▼
    [P propositions]
         │
         ▼
rating_minimum >= 2  ←── Ensures MOVDA has pairwise comparison data
         │
         ▼
    [Winner selected]
         │
         ▼
confirmation_rounds_required (1-2)  ←── Consecutive wins for consensus
```

---

## Database Constraints

All constraints are enforced at the database level in `chats` table:

```sql
CONSTRAINT chats_auto_start_min CHECK (auto_start_participant_count >= 3)
CONSTRAINT chats_proposing_minimum_check CHECK (proposing_minimum >= 3)
CONSTRAINT chats_rating_minimum_check CHECK (rating_minimum >= 2)
CONSTRAINT chats_confirmation_rounds_check CHECK (
  confirmation_rounds_required >= 1 AND confirmation_rounds_required <= 2
)
CONSTRAINT chats_proposing_threshold_count_check CHECK (
  proposing_threshold_count IS NULL OR proposing_threshold_count >= 3
)
CONSTRAINT chats_rating_threshold_count_check CHECK (
  rating_threshold_count IS NULL OR rating_threshold_count >= 2
)
```

---

## Testing

Relevant test files:
- `supabase/tests/26_proposing_minimum_test.sql` - Proposing minimum constraints
- `supabase/tests/26_exclude_original_author_carried_test.sql` - Carried prop author exclusion
- `supabase/tests/28_immediate_early_advance_test.sql` - Auto-advance threshold logic
- `supabase/tests/12_settings_constraints_test.sql` - All settings constraints

---

## Common Questions

**Q: Can I have 2 users test the app?**
A: No. Minimum 3 users required for rating to work.

**Q: Why does the timer keep extending?**
A: Minimum not met. Check proposing_minimum (3 props) or rating_minimum (2 avg ratings).

**Q: Can the original author rate their carried proposition?**
A: No. The system traces back through carried_from_id to exclude them.

**Q: What if everyone ties?**
A: Tie doesn't count toward consensus. Next round starts, all tied winners carried forward.
