#!/usr/bin/env python3
"""
Scenario generator for proposing phase skip feature.

Tests different approaches to handling skips in early advance logic.
Flags problematic outcomes.
"""

import math
from dataclasses import dataclass
from typing import Optional
from itertools import product


@dataclass
class ChatSettings:
    """Host-configured settings"""
    threshold_percent: int  # e.g., 80 means 80%
    threshold_count: int    # minimum submissions for early advance
    proposing_minimum: int  # minimum propositions to advance (timer or early)


@dataclass
class RoundState:
    """Current state of a proposing round"""
    total_participants: int
    submitted: int
    skipped: int

    @property
    def inactive(self) -> int:
        return self.total_participants - self.submitted - self.skipped

    @property
    def participated(self) -> int:
        """Users who made a decision (submit or skip)"""
        return self.submitted + self.skipped


@dataclass
class AdvanceResult:
    """Result of advance check"""
    should_advance: bool
    percent_met: bool
    count_met: bool
    minimum_met: bool
    effective_count_threshold: int
    percent_value: float
    reason: str


def current_logic(settings: ChatSettings, state: RoundState) -> AdvanceResult:
    """
    Current implementation (no skip feature).
    - Percent check: submitted / total >= threshold_percent
    - Count check: submitted >= threshold_count
    - Uses MAX(percent_required, count_required)
    """
    percent_required = math.ceil(state.total_participants * settings.threshold_percent / 100)
    count_required = settings.threshold_count

    # MAX logic - more restrictive wins
    effective_required = max(percent_required, count_required)

    percent_value = (state.submitted / state.total_participants * 100) if state.total_participants > 0 else 0
    percent_met = state.submitted >= percent_required
    count_met = state.submitted >= count_required
    threshold_met = state.submitted >= effective_required
    minimum_met = state.submitted >= settings.proposing_minimum

    should_advance = threshold_met and minimum_met

    reason = []
    if not percent_met:
        reason.append(f"percent {state.submitted}/{percent_required}")
    if not count_met:
        reason.append(f"count {state.submitted}/{count_required}")
    if not minimum_met:
        reason.append(f"minimum {state.submitted}/{settings.proposing_minimum}")

    return AdvanceResult(
        should_advance=should_advance,
        percent_met=percent_met,
        count_met=count_met,
        minimum_met=minimum_met,
        effective_count_threshold=effective_required,
        percent_value=percent_value,
        reason=", ".join(reason) if reason else "all met"
    )


def proposal_a(settings: ChatSettings, state: RoundState) -> AdvanceResult:
    """
    Proposal A: Skips count toward percent, not toward count.
    - Percent check: (submitted + skipped) / total >= threshold_percent
    - Count check: submitted >= threshold_count
    - Dynamic adjustment: effective_count = MIN(threshold_count, total - skipped)
    """
    # Percent based on participation (submitted + skipped)
    percent_required = math.ceil(state.total_participants * settings.threshold_percent / 100)

    # Dynamic count adjustment - can't require more than what's possible
    max_possible = state.total_participants - state.skipped
    effective_count = min(settings.threshold_count, max_possible)

    # Also can't require more than total participants
    effective_count = min(effective_count, state.total_participants)

    # MAX logic with adjusted count
    percent_based_required = percent_required  # participants who participated
    effective_required = max(percent_required, effective_count)

    percent_value = (state.participated / state.total_participants * 100) if state.total_participants > 0 else 0
    percent_met = state.participated >= percent_required
    count_met = state.submitted >= effective_count
    minimum_met = state.submitted >= settings.proposing_minimum

    # Both threshold checks use their respective metrics
    threshold_met = percent_met and count_met
    should_advance = threshold_met and minimum_met

    reason = []
    if not percent_met:
        reason.append(f"percent {state.participated}/{percent_required} participated")
    if not count_met:
        reason.append(f"count {state.submitted}/{effective_count} submitted")
    if not minimum_met:
        reason.append(f"minimum {state.submitted}/{settings.proposing_minimum}")

    return AdvanceResult(
        should_advance=should_advance,
        percent_met=percent_met,
        count_met=count_met,
        minimum_met=minimum_met,
        effective_count_threshold=effective_count,
        percent_value=percent_value,
        reason=", ".join(reason) if reason else "all met"
    )


def proposal_b(settings: ChatSettings, state: RoundState) -> AdvanceResult:
    """
    Proposal B: Skips count toward percent, with reduced denominator.
    - Percent check: submitted / (total - skipped) >= threshold_percent
    - Count check: submitted >= MIN(threshold_count, total - skipped)
    - Percent measures "of those who could submit, how many did?"
    """
    potential_submitters = state.total_participants - state.skipped

    if potential_submitters == 0:
        # Everyone skipped - special case
        return AdvanceResult(
            should_advance=False,
            percent_met=True,  # vacuously true
            count_met=False,
            minimum_met=False,
            effective_count_threshold=0,
            percent_value=100.0,
            reason="everyone skipped, no propositions"
        )

    # Percent of potential submitters who actually submitted
    percent_required_count = math.ceil(potential_submitters * settings.threshold_percent / 100)

    # Dynamic count adjustment
    effective_count = min(settings.threshold_count, potential_submitters)

    percent_value = (state.submitted / potential_submitters * 100)
    percent_met = state.submitted >= percent_required_count
    count_met = state.submitted >= effective_count
    minimum_met = state.submitted >= settings.proposing_minimum

    threshold_met = percent_met and count_met
    should_advance = threshold_met and minimum_met

    reason = []
    if not percent_met:
        reason.append(f"percent {state.submitted}/{percent_required_count} of potential")
    if not count_met:
        reason.append(f"count {state.submitted}/{effective_count} submitted")
    if not minimum_met:
        reason.append(f"minimum {state.submitted}/{settings.proposing_minimum}")

    return AdvanceResult(
        should_advance=should_advance,
        percent_met=percent_met,
        count_met=count_met,
        minimum_met=minimum_met,
        effective_count_threshold=effective_count,
        percent_value=percent_value,
        reason=", ".join(reason) if reason else "all met"
    )


def check_problems(settings: ChatSettings, state: RoundState, result: AdvanceResult, approach: str) -> list[str]:
    """Check for problematic outcomes"""
    problems = []

    # Problem: Advancing with too few propositions for meaningful rating
    if result.should_advance and state.submitted < 3:
        problems.append(f"CRITICAL: Advances with only {state.submitted} propositions (need 3 for rating)")

    # Problem: Impossible to ever advance (threshold > total participants)
    if result.effective_count_threshold > state.total_participants:
        problems.append(f"IMPOSSIBLE: Need {result.effective_count_threshold} but only {state.total_participants} participants")

    # Problem: Threshold higher than possible submissions (after skips)
    max_possible = state.total_participants - state.skipped
    if result.effective_count_threshold > max_possible and state.skipped > 0:
        problems.append(f"STUCK: Need {result.effective_count_threshold} submissions but max possible is {max_possible} (after {state.skipped} skips)")

    # Warning: Everyone who could submit has submitted, but still not advancing
    if state.submitted == max_possible and not result.should_advance and state.submitted > 0:
        problems.append(f"WARNING: All potential submitters ({state.submitted}) submitted but not advancing: {result.reason}")

    # Warning: Very low participation advancing
    if result.should_advance and state.submitted < state.total_participants * 0.3:
        problems.append(f"WARNING: Advancing with only {state.submitted}/{state.total_participants} ({result.percent_value:.0f}%) submissions")

    return problems


def run_scenario(settings: ChatSettings, state: RoundState, verbose: bool = True):
    """Run all approaches on a scenario and compare"""

    results = {
        "current": current_logic(settings, state),
        "proposal_a": proposal_a(settings, state),
        "proposal_b": proposal_b(settings, state),
    }

    all_problems = {}
    for approach, result in results.items():
        problems = check_problems(settings, state, result, approach)
        if problems:
            all_problems[approach] = problems

    if verbose or all_problems:
        print(f"\n{'='*70}")
        print(f"Settings: {settings.threshold_percent}% threshold, count={settings.threshold_count}, min={settings.proposing_minimum}")
        print(f"State: {state.total_participants} participants, {state.submitted} submitted, {state.skipped} skipped, {state.inactive} inactive")
        print("-" * 70)

        for approach, result in results.items():
            advance_str = "✓ ADVANCE" if result.should_advance else "✗ WAIT"
            print(f"{approach:12} | {advance_str} | effective_count={result.effective_count_threshold} | {result.reason}")

            if approach in all_problems:
                for problem in all_problems[approach]:
                    print(f"             | ⚠️  {problem}")

    return results, all_problems


def main():
    print("=" * 70)
    print("SKIP FEATURE SCENARIO ANALYSIS")
    print("=" * 70)

    # Manual interesting scenarios
    print("\n\n### MANUAL SCENARIOS ###")

    # Scenario 1: Normal case - some skip, some submit
    run_scenario(
        ChatSettings(threshold_percent=80, threshold_count=5, proposing_minimum=3),
        RoundState(total_participants=10, submitted=6, skipped=2)
    )

    # Scenario 2: Everyone who didn't skip has submitted
    run_scenario(
        ChatSettings(threshold_percent=80, threshold_count=5, proposing_minimum=3),
        RoundState(total_participants=10, submitted=5, skipped=5)
    )

    # Scenario 3: High threshold, many skips - impossible under current logic
    run_scenario(
        ChatSettings(threshold_percent=80, threshold_count=8, proposing_minimum=3),
        RoundState(total_participants=10, submitted=5, skipped=4)
    )

    # Scenario 4: Everyone skips
    run_scenario(
        ChatSettings(threshold_percent=80, threshold_count=5, proposing_minimum=3),
        RoundState(total_participants=10, submitted=0, skipped=10)
    )

    # Scenario 5: Minimum participants (3), all submit
    run_scenario(
        ChatSettings(threshold_percent=80, threshold_count=3, proposing_minimum=3),
        RoundState(total_participants=3, submitted=3, skipped=0)
    )

    # Scenario 6: Minimum participants, 1 skips
    run_scenario(
        ChatSettings(threshold_percent=80, threshold_count=3, proposing_minimum=3),
        RoundState(total_participants=3, submitted=2, skipped=1)
    )

    # Scenario 7: Low threshold, many skips
    run_scenario(
        ChatSettings(threshold_percent=50, threshold_count=3, proposing_minimum=3),
        RoundState(total_participants=10, submitted=3, skipped=6)
    )

    # Scenario 8: Small group, high percent threshold
    run_scenario(
        ChatSettings(threshold_percent=100, threshold_count=3, proposing_minimum=3),
        RoundState(total_participants=5, submitted=4, skipped=1)
    )

    # Exhaustive search for problems
    print("\n\n### EXHAUSTIVE SEARCH FOR PROBLEMS ###")
    print("(Only showing scenarios with problems)\n")

    problem_count = {"current": 0, "proposal_a": 0, "proposal_b": 0}
    total_scenarios = 0

    # Generate many scenarios
    for total in range(3, 12):  # 3-11 participants
        for threshold_pct in [50, 60, 70, 80, 90, 100]:
            for threshold_cnt in range(3, min(total + 1, 10)):
                for submitted in range(0, total + 1):
                    for skipped in range(0, total - submitted + 1):
                        total_scenarios += 1

                        settings = ChatSettings(
                            threshold_percent=threshold_pct,
                            threshold_count=threshold_cnt,
                            proposing_minimum=3
                        )
                        state = RoundState(
                            total_participants=total,
                            submitted=submitted,
                            skipped=skipped
                        )

                        _, problems = run_scenario(settings, state, verbose=False)

                        for approach, prob_list in problems.items():
                            # Only count critical problems
                            critical = [p for p in prob_list if "CRITICAL" in p or "STUCK" in p]
                            if critical:
                                problem_count[approach] += 1
                                # Print first few
                                if problem_count[approach] <= 3:
                                    run_scenario(settings, state, verbose=True)

    print(f"\n\n### SUMMARY ###")
    print(f"Total scenarios tested: {total_scenarios}")
    print(f"Critical/Stuck problems found:")
    for approach, count in problem_count.items():
        print(f"  {approach}: {count}")

    # Show key differences between proposals
    print("\n\n### KEY DIFFERENCES ###")
    print("Scenarios where proposals differ:\n")

    diff_count = 0
    for total in [5, 8, 10]:
        for threshold_pct in [80]:
            for threshold_cnt in [5]:
                for submitted in range(0, total + 1):
                    for skipped in range(0, total - submitted + 1):
                        settings = ChatSettings(
                            threshold_percent=threshold_pct,
                            threshold_count=threshold_cnt,
                            proposing_minimum=3
                        )
                        state = RoundState(
                            total_participants=total,
                            submitted=submitted,
                            skipped=skipped
                        )

                        results, _ = run_scenario(settings, state, verbose=False)

                        outcomes = [r.should_advance for r in results.values()]
                        if len(set(outcomes)) > 1:  # Different outcomes
                            diff_count += 1
                            if diff_count <= 10:
                                run_scenario(settings, state, verbose=True)

    print(f"\nTotal scenarios with different outcomes: {diff_count}")


if __name__ == "__main__":
    main()
