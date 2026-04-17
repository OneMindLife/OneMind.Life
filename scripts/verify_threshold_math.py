#!/usr/bin/env python3
"""
Mathematically verify the per-proposition threshold formula.

Goal: Prove that threshold = min(10, max(active_raters - 1, 1))
always equals min(max_possible_raters(prop)) across all propositions,
for every combination of participants, skippers, and carry-forwards.

If threshold > min(max_possible), the threshold is unreachable (BUG).
If threshold < min(max_possible), we're leaving quality on the table.
"""

from itertools import combinations
from dataclasses import dataclass


@dataclass
class Prop:
    id: int
    author_id: int


def max_raters_for_prop(prop, participants, skippers):
    """Max possible raters for a proposition = active non-skipped non-authors."""
    return len([
        p for p in participants
        if p not in skippers and p != prop.author_id
    ])


def compute_threshold(active_raters):
    """Current formula."""
    return min(10, max(active_raters - 1, 1))


def verify_scenario(n_participants, n_carry, carry_author, skippers,
                    proposing_participants=None):
    """
    Verify threshold is mathematically exact for a scenario.
    Returns (is_exact, threshold, min_max_possible, details).
    """
    participants = list(range(1, n_participants + 1))
    if proposing_participants is None:
        proposing_participants = participants

    # Create propositions
    props = []
    pid = 1
    for p in proposing_participants:
        props.append(Prop(pid, p))
        pid += 1
    for i in range(n_carry):
        props.append(Prop(pid, carry_author))
        pid += 1

    # Active raters
    active_raters = [p for p in participants if p not in skippers]
    n_active = len(active_raters)

    if n_active == 0:
        return (True, 0, 0, "No active raters — advance immediately")

    threshold = compute_threshold(n_active)

    # Min max possible across all propositions
    max_possibles = {}
    for prop in props:
        mr = max_raters_for_prop(prop, participants, skippers)
        max_possibles[f"P{prop.id}(by {prop.author_id})"] = mr

    min_max = min(max_possibles.values()) if max_possibles else 0

    is_exact = threshold == min_max
    is_safe = threshold <= min_max  # at least achievable

    details = {
        "participants": participants,
        "skippers": list(skippers),
        "active_raters": n_active,
        "threshold": threshold,
        "min_max_possible": min_max,
        "per_prop_max": max_possibles,
        "exact": is_exact,
        "safe": is_safe,
    }

    return (is_exact, is_safe, threshold, min_max, details)


def run_all():
    print("=" * 70)
    print("THRESHOLD FORMULA MATHEMATICAL VERIFICATION")
    print("Formula: threshold = min(10, max(active_raters - 1, 1))")
    print("Checking: threshold == min(max_possible_raters per prop)")
    print("=" * 70)

    total_checks = 0
    exact_count = 0
    safe_count = 0
    failures = []

    # =================================================================
    # Exhaustive check: all combos of 2-8 participants, 0-3 carries,
    # all possible skipper subsets
    # =================================================================
    for n in range(2, 9):
        participants = list(range(1, n + 1))
        for n_carry in range(0, 4):
            for carry_author in range(1, n + 1):
                # All possible skipper subsets (0 to n-1 skippers)
                for n_skip in range(0, n):
                    for skippers in combinations(participants, n_skip):
                        skipper_set = set(skippers)

                        # Test with all proposing
                        result = verify_scenario(n, n_carry, carry_author, skipper_set)
                        is_exact, is_safe, threshold, min_max, details = result
                        total_checks += 1
                        if is_exact:
                            exact_count += 1
                        if is_safe:
                            safe_count += 1
                        else:
                            failures.append(("all_propose", n, n_carry, carry_author,
                                             list(skipper_set), details))

                        # Test with only first half proposing
                        if n >= 3:
                            proposers = participants[:n // 2 + 1]
                            result2 = verify_scenario(n, n_carry, carry_author,
                                                       skipper_set, proposers)
                            is_exact2, is_safe2, _, _, details2 = result2
                            total_checks += 1
                            if is_exact2:
                                exact_count += 1
                            if is_safe2:
                                safe_count += 1
                            else:
                                failures.append(("partial_propose", n, n_carry,
                                                 carry_author, list(skipper_set), details2))

    print(f"\nTotal scenarios checked: {total_checks}")
    print(f"Exact matches (threshold == min_max): {exact_count}")
    print(f"Safe (threshold <= min_max): {safe_count}")
    print(f"UNSAFE (threshold > min_max): {len(failures)}")

    if failures:
        print(f"\n{'!'*70}")
        print("FAILURES FOUND:")
        for f in failures[:20]:
            print(f"\n  Type: {f[0]}, {f[1]}p, {f[2]}c, carry_author={f[3]}, skip={f[4]}")
            d = f[5]
            print(f"  threshold={d['threshold']}, min_max_possible={d['min_max_possible']}")
            print(f"  per_prop: {d['per_prop_max']}")
    else:
        print("\n  ALL SCENARIOS SAFE — threshold is always achievable")

    # =================================================================
    # Check exactness gap: how often is threshold < min_max?
    # =================================================================
    gap_count = safe_count - exact_count
    if gap_count > 0:
        print(f"\n  Note: {gap_count} scenarios have threshold < min_max_possible")
        print("  This means we could set a higher threshold without blocking.")
        print("  Investigating when this happens...")

        # Find examples
        examples_shown = 0
        for n in range(2, 9):
            participants = list(range(1, n + 1))
            for n_carry in range(0, 4):
                for carry_author in range(1, n + 1):
                    for n_skip in range(0, n):
                        for skippers in combinations(participants, n_skip):
                            result = verify_scenario(n, n_carry, carry_author, set(skippers))
                            is_exact, is_safe, threshold, min_max, details = result
                            if is_safe and not is_exact and examples_shown < 5:
                                print(f"\n  Example: {n}p, {n_carry}c, author={carry_author}, "
                                      f"skip={list(skippers)}")
                                print(f"    threshold={threshold}, min_max={min_max}")
                                print(f"    per_prop: {details['per_prop_max']}")
                                examples_shown += 1

    # =================================================================
    # Specific edge cases from our discussion
    # =================================================================
    print(f"\n{'='*70}")
    print("SPECIFIC EDGE CASES")
    print("=" * 70)

    cases = [
        ("4 users, 1 carry by P1, P4 skips", 4, 1, 1, {4}, None),
        ("4 users, 2 carries by P1, P3+P4 skip", 4, 2, 1, {3, 4}, None),
        ("4 users, only P1+P2 proposed, 1 carry by P1", 4, 1, 1, set(), [1, 2]),
        ("4 users, only P1+P2 proposed, 1 carry by P1, P4 skips", 4, 1, 1, {4}, [1, 2]),
        ("3 users, 2 carries by P1, all rate", 3, 2, 1, set(), None),
        ("5 users, 1 carry by P1, P1 skips (carry author skips)", 5, 1, 1, {1}, None),
        ("12 users, 0 carry, 0 skip (threshold cap at 10)", 12, 0, 1, set(), None),
        ("12 users, 0 carry, 3 skip", 12, 0, 1, {10, 11, 12}, None),
        ("5 users, 3 carries by P1, P5 skips", 5, 3, 1, {5}, None),
    ]

    for desc, n, nc, ca, skip, proposers in cases:
        result = verify_scenario(n, nc, ca, skip, proposers)
        is_exact, is_safe, threshold, min_max, details = result
        status = "EXACT ✓" if is_exact else ("SAFE ✓" if is_safe else "UNSAFE ✗")
        print(f"\n  {desc}")
        print(f"    active_raters={details['active_raters']}, "
              f"threshold={threshold}, min_max={min_max} → {status}")
        if not is_exact:
            print(f"    per_prop: {details['per_prop_max']}")

    # =================================================================
    # The real question: should threshold = min_max or active_raters-1?
    # =================================================================
    print(f"\n{'='*70}")
    print("RECOMMENDATION")
    print("=" * 70)

    # Count how many scenarios would benefit from using min_max directly
    benefit_count = 0
    total_small = 0
    for n in range(2, 9):
        participants = list(range(1, n + 1))
        for n_carry in range(0, 4):
            for carry_author in range(1, n + 1):
                for n_skip in range(0, n):
                    for skippers in combinations(participants, n_skip):
                        result = verify_scenario(n, n_carry, carry_author, set(skippers))
                        is_exact, is_safe, threshold, min_max, details = result
                        total_small += 1
                        if min_max > threshold and is_safe:
                            benefit_count += 1

    print(f"\n  Scenarios where min_max > threshold (could use higher threshold):")
    print(f"  {benefit_count}/{total_small} ({benefit_count*100/total_small:.1f}%)")

    if benefit_count > 0:
        print(f"\n  These are cases where carry-forward authors skip rating,")
        print(f"  making their props available to MORE raters than active_raters-1.")
        print(f"  Using min_max directly would give slightly higher quality.")
        print(f"\n  To use min_max, the DB trigger would need to compute")
        print(f"  min(max_possible_raters) per proposition instead of using")
        print(f"  active_raters - 1 as a proxy.")

    print(f"\n{'='*70}")
    if not failures:
        print("RESULT: Formula is SAFE (always achievable). Never blocks advance.")
    else:
        print("RESULT: UNSAFE — formula can set unreachable thresholds!")
    print("=" * 70)


if __name__ == "__main__":
    run_all()
