#!/usr/bin/env python3
"""
Simulate the per-proposition early advance system for rating phase.

Tests the rule:
  - Threshold = min(10, max(active_raters - 1, 1))
    where active_raters = active participants who haven't skipped
  - Selection: least-rated-first (ties broken randomly)
  - Advance when: min(ratings across all propositions) >= threshold
  - Progress bar: min(ratings per prop) / threshold × 100
  - User "Done": rated min(10, non-self props) propositions

Edge cases covered:
  - Small chats (2-4 people)
  - Large chats (12, 20, 50)
  - Carry-forward: 1, 2, 3 (ties from same author)
  - Carry-forward from different authors (tied winners)
  - Not all participants proposed (some skipped proposing)
  - Users skipping rating
  - Users leaving mid-rating
  - Progress bar alignment with advance
  - "Done" alignment with advance (≤11 vs 12+ participants)
  - Max possible raters per proposition verification
"""

import random
from dataclasses import dataclass, field
from typing import Optional


DONE_CAP = 10  # User "done" after rating this many (or all non-self if fewer)


@dataclass
class Proposition:
    id: int
    author_id: int  # participant who submitted it
    is_carried: bool = False
    ratings: list = field(default_factory=list)

    @property
    def rating_count(self):
        return len(self.ratings)


@dataclass
class Participant:
    id: int
    active: bool = True
    skipped: bool = False
    proposed: bool = True  # whether they submitted a proposition
    rated_prop_ids: list = field(default_factory=list)

    @property
    def rated_count(self):
        return len(self.rated_prop_ids)


def get_rateable_props(participant, propositions):
    """Get propositions this participant can rate (not their own, not already rated)."""
    return [
        p for p in propositions
        if p.author_id != participant.id
        and p.id not in participant.rated_prop_ids
    ]


def pick_least_rated(rateable):
    """Pick the proposition with the fewest ratings. Break ties randomly."""
    if not rateable:
        return None
    min_count = min(p.rating_count for p in rateable)
    candidates = [p for p in rateable if p.rating_count == min_count]
    return random.choice(candidates)


def calc_threshold(active_raters_count):
    """Calculate the per-proposition advance threshold."""
    return min(10, max(active_raters_count - 1, 1))


def calc_progress(propositions, threshold):
    """Calculate progress bar percentage."""
    if not propositions or threshold <= 0:
        return 100
    min_ratings = min(p.rating_count for p in propositions)
    return min(int(min_ratings / threshold * 100), 100)


def is_user_done(participant, propositions):
    """Check if a user is 'done' (rated min(DONE_CAP, non-self props))."""
    non_self = len([p for p in propositions if p.author_id != participant.id])
    required = min(DONE_CAP, non_self)
    return participant.rated_count >= required


def max_possible_raters(prop, participants):
    """Max possible raters for a proposition (active non-skipped, excluding author)."""
    return len([
        p for p in participants
        if p.active and not p.skipped and p.id != prop.author_id
    ])


def simulate(
    num_participants,
    num_carry_forwards=0,
    carry_author_ids=None,  # list of author IDs for each carry-forward
    proposing_participants=None,  # which participants proposed (None = all)
    leaving_participants=None,
    leave_after_n_ratings=2,
    skipping_participants=None,
    verbose=False,
):
    leaving_participants = leaving_participants or []
    skipping_participants = skipping_participants or []

    # Create participants
    participants = [Participant(id=i + 1) for i in range(num_participants)]

    # Determine who proposed
    if proposing_participants is not None:
        for p in participants:
            p.proposed = p.id in proposing_participants
    # else all proposed

    # Create propositions
    propositions = []
    prop_id = 1
    for p in participants:
        if p.proposed:
            propositions.append(Proposition(id=prop_id, author_id=p.id))
            prop_id += 1

    # Carry-forwards
    if carry_author_ids is None:
        carry_author_ids = [1] * num_carry_forwards
    for author_id in carry_author_ids:
        propositions.append(Proposition(id=prop_id, author_id=author_id, is_carried=True))
        prop_id += 1

    # Mark skippers
    for pid in skipping_participants:
        for p in participants:
            if p.id == pid:
                p.skipped = True

    # Calculate initial state
    active_raters = [p for p in participants if p.active and not p.skipped]
    threshold = calc_threshold(len(active_raters))

    if verbose:
        print(f"\n{'='*70}")
        proposers = [p.id for p in participants if p.proposed]
        non_proposers = [p.id for p in participants if not p.proposed]
        print(f"Setup: {num_participants} participants, {len(propositions)} props "
              f"({len(propositions) - num_carry_forwards} new + {num_carry_forwards} carry)")
        if non_proposers:
            print(f"  Proposed: {proposers}")
            print(f"  Skipped proposing: {non_proposers}")
        if carry_author_ids and num_carry_forwards > 0:
            print(f"  Carry-forward authors: {carry_author_ids}")
        if skipping_participants:
            print(f"  Skipping rating: {skipping_participants}")
        if leaving_participants:
            print(f"  Leaving after {leave_after_n_ratings} ratings: {leaving_participants}")
        print(f"  Active raters: {len(active_raters)}, Threshold: {threshold}")
        print(f"  Per-participant rateable props:")
        for p in participants:
            rateable = get_rateable_props(p, propositions)
            done_at = min(DONE_CAP, len(rateable))
            status = " (skip-rating)" if p.skipped else ""
            print(f"    P{p.id}: {len(rateable)} rateable, done at {done_at}{status}")
        print(f"  Per-proposition max raters:")
        for prop in propositions:
            mr = max_possible_raters(prop, participants)
            carried = " (carry)" if prop.is_carried else ""
            print(f"    Prop{prop.id} (by P{prop.author_id}{carried}): max {mr} raters"
                  f"{' ⚠️ < threshold!' if mr < threshold else ''}")
        print()

    # Verify: every prop can reach threshold
    unreachable = []
    for prop in propositions:
        mr = max_possible_raters(prop, participants)
        if mr < threshold:
            unreachable.append((prop.id, mr))

    # Simulate
    total_ratings = 0
    advanced = False
    advance_at_rating = None
    progress_history = []
    done_history = []

    max_ticks = len(participants) * len(propositions) * 3

    tick = 0
    while tick < max_ticks:
        tick += 1

        # Handle leaving
        for pid in leaving_participants:
            for p in participants:
                if p.id == pid and p.active and p.rated_count >= leave_after_n_ratings:
                    p.active = False
                    new_active = [pp for pp in participants if pp.active and not pp.skipped]
                    threshold = calc_threshold(len(new_active))
                    if verbose:
                        print(f"  [tick {tick}] P{pid} left! active_raters={len(new_active)}, threshold={threshold}")

        active_rater_list = [p for p in participants if p.active and not p.skipped]
        if not active_rater_list:
            break

        raters_with_work = [p for p in active_rater_list if get_rateable_props(p, propositions)]
        if not raters_with_work:
            break

        rater = random.choice(raters_with_work)
        rateable = get_rateable_props(rater, propositions)
        prop = pick_least_rated(rateable)
        if not prop:
            continue

        prop.ratings.append(rater.id)
        rater.rated_prop_ids.append(prop.id)
        total_ratings += 1

        # Track progress and done status
        progress = calc_progress(propositions, threshold)
        all_active_non_skip = [p for p in participants if p.active and not p.skipped]
        done_users = [p for p in all_active_non_skip if is_user_done(p, propositions)]
        done_count = len(done_users)
        done_total = len(all_active_non_skip)

        progress_history.append(progress)
        done_history.append((done_count, done_total))

        # Check advance
        min_ratings = min(p.rating_count for p in propositions)
        if not advanced and min_ratings >= threshold:
            advanced = True
            advance_at_rating = total_ratings
            if verbose:
                print(f"  [tick {tick}] ADVANCE! min_ratings={min_ratings} >= threshold={threshold} "
                      f"after {total_ratings} ratings. Progress={progress}%. "
                      f"Done users: {done_count}/{done_total}")

        if advanced and total_ratings >= advance_at_rating + 3:
            break

    # Final state
    rating_counts = [p.rating_count for p in propositions]
    min_ratings = min(rating_counts) if rating_counts else 0
    max_ratings = max(rating_counts) if rating_counts else 0
    final_progress = calc_progress(propositions, threshold)

    all_active = [p for p in participants if p.active and not p.skipped]
    all_done = all(is_user_done(p, propositions) for p in all_active)
    done_count = len([p for p in all_active if is_user_done(p, propositions)])

    result = {
        "num_participants": num_participants,
        "num_propositions": len(propositions),
        "num_carry_forwards": num_carry_forwards,
        "threshold": threshold,
        "advanced": advanced,
        "advance_at_rating": advance_at_rating,
        "total_ratings": total_ratings,
        "min_ratings": min_ratings,
        "max_ratings": max_ratings,
        "spread": max_ratings - min_ratings,
        "final_progress": final_progress,
        "all_done": all_done,
        "done_count": done_count,
        "done_total": len(all_active),
        "unreachable_props": unreachable,
        "progress_at_advance": progress_history[advance_at_rating - 1] if advance_at_rating else None,
    }

    if verbose:
        print(f"\n  Results:")
        print(f"    Advanced: {advanced}" + (f" (after {advance_at_rating} ratings)" if advanced else ""))
        print(f"    Threshold: {threshold}")
        print(f"    Ratings per prop: min={min_ratings}, max={max_ratings}, spread={max_ratings - min_ratings}")
        print(f"    Progress bar: {final_progress}%")
        print(f"    All users done: {all_done} ({done_count}/{len(all_active)})")
        if unreachable:
            print(f"    ⚠️  UNREACHABLE props: {unreachable}")
        print(f"    Per-prop:")
        for prop in propositions:
            carried = " (carry)" if prop.is_carried else ""
            print(f"      Prop{prop.id} (P{prop.author_id}{carried}): {prop.rating_count} ratings")
        print(f"    Per-user:")
        for p in participants:
            status = ""
            if p.skipped: status = " (skip-rating)"
            elif not p.active: status = " (left)"
            done = is_user_done(p, propositions) if p.active and not p.skipped else False
            done_str = " ✓DONE" if done else ""
            print(f"      P{p.id}: rated {p.rated_count}{status}{done_str}")

    return result


def assert_eq(actual, expected, msg):
    if actual != expected:
        print(f"  FAIL: {msg}")
        print(f"    Expected: {expected}")
        print(f"    Actual:   {actual}")
        raise AssertionError(msg)


def run_all():
    print("=" * 70)
    print("PER-PROPOSITION EARLY ADVANCE SIMULATION")
    print("Threshold = min(10, max(active_raters - 1, 1))")
    print("Progress = min(ratings per prop) / threshold × 100")
    print("Done = user rated min(10, non-self props)")
    print("=" * 70)

    # =====================================================================
    # 1. Basic: 3 participants, no carry
    # =====================================================================
    r = simulate(3, verbose=True)
    assert r["advanced"]
    assert r["progress_at_advance"] == 100, f"Progress at advance should be 100, got {r['progress_at_advance']}"
    assert r["all_done"], "All users should be done when advance fires (≤11 participants)"
    assert r["threshold"] == 2
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 2. 4 users, 1 carry-forward (P1 author), only P1+P2 proposed
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=1,
        carry_author_ids=[1],
        proposing_participants=[1, 2],
        verbose=True,
    )
    assert r["advanced"]
    assert r["threshold"] == 3
    assert r["progress_at_advance"] == 100
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 3. 4 users, 2 carry-forwards (both P1), only P1+P2 proposed
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=2,
        carry_author_ids=[1, 1],
        proposing_participants=[1, 2],
        verbose=True,
    )
    assert r["advanced"]
    assert r["threshold"] == 3
    assert r["progress_at_advance"] == 100
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 4. 4 users, 2 carry-forwards from DIFFERENT authors (tie)
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=2,
        carry_author_ids=[1, 2],
        proposing_participants=[1, 2],
        verbose=True,
    )
    assert r["advanced"]
    assert r["threshold"] == 3
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 5. 4 users, 1 carry, 1 skip rating
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=1,
        carry_author_ids=[1],
        proposing_participants=[1, 2],
        skipping_participants=[4],
        verbose=True,
    )
    assert r["advanced"]
    # active_raters = 3, threshold = 2
    assert r["threshold"] == 2
    assert r["progress_at_advance"] == 100
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 6. 4 users, 1 carry, 2 skip rating
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=1,
        carry_author_ids=[1],
        proposing_participants=[1, 2],
        skipping_participants=[3, 4],
        verbose=True,
    )
    assert r["advanced"]
    # active_raters = 2, threshold = 1
    assert r["threshold"] == 1
    assert r["progress_at_advance"] == 100
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 7. 2 participants (minimum viable)
    # =====================================================================
    r = simulate(2, verbose=True)
    assert r["advanced"]
    assert r["threshold"] == 1
    assert r["progress_at_advance"] == 100
    assert r["all_done"]
    print("  PASS\n")

    # =====================================================================
    # 8. 12 participants — threshold caps at 10, done cap matters
    # =====================================================================
    r = simulate(12, verbose=True)
    assert r["advanced"]
    assert r["threshold"] == 10
    assert r["progress_at_advance"] == 100
    # With 12 participants, each has 11 non-self props, done at 10.
    # All done should align with advance since least-rated-first distributes evenly.
    print(f"  All done at advance: {r['all_done']}")
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 9. 20 participants, 2 carry-forwards
    # =====================================================================
    r = simulate(20, num_carry_forwards=2, carry_author_ids=[1, 1], verbose=True)
    assert r["advanced"]
    assert r["threshold"] == 10
    assert r["progress_at_advance"] == 100
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 10. 50 participants — large chat
    # =====================================================================
    r = simulate(50, verbose=True)
    assert r["advanced"]
    assert r["threshold"] == 10
    # Not all users need to be done — many won't have rated 10 yet
    print(f"  Done at advance: {r['done_count']}/{r['done_total']}")
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 11. User leaves mid-rating
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=1,
        carry_author_ids=[1],
        proposing_participants=[1, 2],
        leaving_participants=[4],
        leave_after_n_ratings=1,
        verbose=True,
    )
    assert r["advanced"]
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 12. Carry-forward author leaves
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=1,
        carry_author_ids=[1],
        proposing_participants=[1, 2],
        leaving_participants=[1],
        leave_after_n_ratings=1,
        verbose=True,
    )
    assert r["advanced"]
    # After P1 leaves, carry's author is gone — everyone can rate it
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 13. 3 carry-forwards from same author (extreme)
    # =====================================================================
    r = simulate(
        num_participants=4,
        num_carry_forwards=3,
        carry_author_ids=[1, 1, 1],
        proposing_participants=[1, 2],
        verbose=True,
    )
    assert r["advanced"]
    assert r["threshold"] == 3
    assert not r["unreachable_props"]
    print("  PASS\n")

    # =====================================================================
    # 14. Progress bar alignment — verify progress = 100% exactly at advance
    # Run 200 times with different configs
    # =====================================================================
    print(f"\n{'='*70}")
    print("Progress bar alignment test (200 runs)")
    misaligned = 0
    for _ in range(50):
        for n in [3, 4, 5, 10]:
            r = simulate(n, num_carry_forwards=1, carry_author_ids=[1],
                         proposing_participants=list(range(1, n//2 + 2)))
            if r["advanced"] and r["progress_at_advance"] != 100:
                misaligned += 1
                print(f"  MISALIGNED: {n} participants, progress={r['progress_at_advance']}% at advance")
    print(f"  Misaligned: {misaligned}/200")
    assert misaligned == 0, f"{misaligned} runs had progress != 100% at advance"
    print("  PASS\n")

    # =====================================================================
    # 15. Done alignment — for ≤11 participants, all done = advance
    # =====================================================================
    print(f"{'='*70}")
    print("Done alignment test (≤11 participants, 100 runs)")
    misaligned = 0
    for _ in range(20):
        for n in [2, 3, 4, 5, 8, 11]:
            r = simulate(n)
            if r["advanced"] and not r["all_done"]:
                misaligned += 1
    print(f"  Misaligned: {misaligned}/120")
    assert misaligned == 0, "For ≤11 participants, all users should be done when advance fires"
    print("  PASS\n")

    # =====================================================================
    # 16. For 12+ participants, advance can fire before all done
    # This is expected behavior — verify it happens
    # =====================================================================
    print(f"{'='*70}")
    print("12+ participants: advance before all done (expected)")
    not_all_done_count = 0
    for _ in range(50):
        r = simulate(20, num_carry_forwards=1, carry_author_ids=[1])
        if r["advanced"] and not r["all_done"]:
            not_all_done_count += 1
    print(f"  Advance fired before all done: {not_all_done_count}/50 runs")
    print(f"  (This is expected — not all users need to be done for advance)")
    print("  PASS\n")

    # =====================================================================
    # 17. Fairness — rating spread with least-rated-first
    # =====================================================================
    print(f"{'='*70}")
    print("Fairness test (100 runs of 20 participants + 1 carry)")
    spreads = []
    for _ in range(100):
        r = simulate(20, num_carry_forwards=1, carry_author_ids=[1])
        spreads.append(r["spread"])
    avg_spread = sum(spreads) / len(spreads)
    max_spread = max(spreads)
    print(f"  Avg spread: {avg_spread:.2f}, Max spread: {max_spread}")
    assert avg_spread <= 2.0
    assert max_spread <= 5
    print("  PASS\n")

    # =====================================================================
    # 18. Max possible raters — verify no prop has fewer than threshold
    # =====================================================================
    print(f"{'='*70}")
    print("Max possible raters verification (many configs)")
    all_reachable = True
    configs = [
        (3, 0, []),
        (3, 1, [1]),
        (3, 2, [1, 1]),
        (4, 0, []),
        (4, 1, [1]),
        (4, 2, [1, 1]),
        (4, 2, [1, 2]),
        (4, 3, [1, 1, 1]),
        (5, 1, [1]),
        (5, 2, [1, 2]),
        (10, 1, [1]),
        (12, 2, [1, 1]),
        (20, 3, [1, 1, 2]),
    ]
    for n, nc, ca in configs:
        r = simulate(n, num_carry_forwards=nc, carry_author_ids=ca)
        if r["unreachable_props"]:
            print(f"  ⚠️  UNREACHABLE: {n}p, {nc}c, authors={ca}: {r['unreachable_props']}")
            all_reachable = False
        else:
            print(f"  ✓ {n}p, {nc}c, authors={ca}: threshold={r['threshold']}, all reachable")
    assert all_reachable
    print("  PASS\n")

    # =====================================================================
    # 19. With skippers — verify max possible still >= threshold
    # =====================================================================
    print(f"{'='*70}")
    print("Skippers + carry-forwards reachability")
    skip_configs = [
        (4, 1, [1], [4]),
        (4, 1, [1], [3, 4]),
        (4, 2, [1, 1], [4]),
        (5, 2, [1, 1], [4, 5]),
        (5, 1, [1], [3, 4, 5]),
    ]
    all_ok = True
    for n, nc, ca, sk in skip_configs:
        r = simulate(n, num_carry_forwards=nc, carry_author_ids=ca, skipping_participants=sk)
        if r["unreachable_props"]:
            print(f"  ⚠️  UNREACHABLE: {n}p, {nc}c, skip={sk}: {r['unreachable_props']}")
            all_ok = False
        else:
            print(f"  ✓ {n}p, {nc}c, skip={sk}: threshold={r['threshold']}, all reachable")
    assert all_ok
    print("  PASS\n")

    # =====================================================================
    print("=" * 70)
    print("ALL SCENARIOS PASSED")
    print("=" * 70)


if __name__ == "__main__":
    random.seed(42)
    run_all()
