# OneMind User Ranking System

## Overview

The OneMind User Ranking System calculates participant performance across rounds using a **50/50 weighted combination** of voting accuracy and proposing quality.

**Core Formula:**
```
round_rank = (voting_rank + proposing_rank) / 2
```

Where both `voting_rank` and `proposing_rank` are scored on a 0-100 scale.

---

## Database Tables

### 1. `user_voting_ranks`

Stores pairwise comparison accuracy for each participant per round.

| Column | Type | Description |
|--------|------|-------------|
| `round_id` | BIGINT | Round reference (FK to rounds) |
| `participant_id` | BIGINT | Participant reference (FK to participants) |
| `rank` | REAL | 0-100 score (100 = perfect accuracy, NULL if didn't vote) |
| `correct_pairs` | INTEGER | Number of pairwise comparisons matching global ordering |
| `total_pairs` | INTEGER | Total pairwise comparisons from user rankings |
| `created_at` | TIMESTAMPTZ | Timestamp |

**Calculation Method:**
- Compare user's ordinal rankings (A > B > C) against global consensus (MOVDA scores)
- Count how many pairwise ordering decisions match the final global order
- Accuracy = (correct_pairs / total_pairs) × 100

### 2. `user_proposing_ranks`

Stores proposition performance for each participant per round.

| Column | Type | Description |
|--------|------|-------------|
| `round_id` | BIGINT | Round reference |
| `participant_id` | BIGINT | Participant reference |
| `rank` | REAL | 0-100 normalized score (NULL if no propositions) |
| `avg_score` | REAL | Average global_score of user's propositions |
| `proposition_count` | INTEGER | Number of original propositions (excludes carryover) |
| `created_at` | TIMESTAMPTZ | Timestamp |

**Calculation Method:**
- Calculate average global score of all propositions user created this round
- Normalize to 0-100 scale across all participants in round
- NULL if user proposed only carryover propositions

### 3. `user_round_ranks`

Stores combined round ranking.

| Column | Type | Description |
|--------|------|-------------|
| `round_id` | BIGINT | Round reference |
| `participant_id` | BIGINT | Participant reference |
| `rank` | REAL | Combined score (0-100) |
| `voting_rank` | REAL | Copy from user_voting_ranks |
| `proposing_rank` | REAL | Copy from user_proposing_ranks |
| `created_at` | TIMESTAMPTZ | Timestamp |

---

## Functions

### `calculate_voting_ranks(p_round_id BIGINT)`

Compares each participant's grid rankings against final MOVDA scores to determine accuracy.

**Algorithm:**
1. For each participant who submitted grid rankings
2. Extract all pairwise comparisons from their grid (A>B, A>C, B>C, etc.)
3. Compare each pair against final global ordering
4. Count matches = `correct_pairs`
5. Total comparisons = `total_pairs`
6. Return: `rank = (correct_pairs / total_pairs) × 100`

### `calculate_proposing_ranks(p_round_id BIGINT)`

Calculates normalized performance based on proposition quality.

**Algorithm:**
1. For each participant who created propositions (excludes carryover):
2. Calculate average global_score of their propositions
3. Find min and max across all participants
4. Normalize to 0-100: `(avg_score - min) / (max - min) × 100`
5. NULL for participants with no original propositions

### `calculate_round_ranks(p_round_id BIGINT)`

Calculates combined ranking.

**Algorithm:**
1. Get voting_ranks and proposing_ranks for round
2. If both exist: `round_rank = (voting_rank + proposing_rank) / 2`
3. If only voting: `round_rank = voting_rank`
4. If only proposing: `round_rank = proposing_rank`
5. NULL if neither

### `store_round_ranks(p_round_id BIGINT)`

Persists calculated ranks to database tables.

**Called automatically:**
- Within `complete_round_with_winner()` after MOVDA calculation
- Ensures rankings are computed immediately when round completes

---

## Integration

The ranking system is automatically triggered when a round completes:

```sql
-- In complete_round_with_winner()
 PERFORM calculate_movda_scores(p_round_id);
 PERFORM store_round_ranks(p_round_id);
```

This ensures rankings are always available immediately after round completion.

---

## Reputation System

User rankings form the basis of the **OneMind reputation system**:

- Participants build reputation through consistent accurate voting
- Proposing quality (not just quantity) matters
- Rankings are per-round, enabling improvement over time
- Historical data available for leaderboards and reputation analytics

---

## Migration

**File:** `supabase/migrations/20260121200000_add_user_ranking.sql`

This migration creates all three tables, indexes, and the four calculation functions.

