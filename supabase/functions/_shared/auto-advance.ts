/**
 * Auto-Advance Logic
 *
 * Determines whether to skip the timer early based on participation thresholds.
 * Uses MAX of percent-based and count-based thresholds (more restrictive).
 */

export interface ThresholdConfig {
  thresholdPercent: number | null;
  thresholdCount: number | null;
}

export interface ParticipationData {
  totalParticipants: number;
  participatedCount: number;
}

export interface SkipAwareParticipationData extends ParticipationData {
  skipCount: number;
  submitterCount: number;
}

/**
 * Calculate the required participation count based on thresholds.
 * Returns the MAX of percent-based and count-based requirements.
 *
 * @param config - The threshold configuration (percent and/or count)
 * @param totalParticipants - Total active participants in the chat
 * @returns The required count to trigger auto-advance, or null if disabled
 */
export function calculateRequiredCount(
  config: ThresholdConfig,
  totalParticipants: number
): number | null {
  const { thresholdPercent, thresholdCount } = config;

  // If both are null, auto-advance is disabled
  if (thresholdPercent === null && thresholdCount === null) {
    return null;
  }

  // Calculate percent-based requirement (rounded up)
  const percentRequired = thresholdPercent !== null
    ? Math.ceil((totalParticipants * thresholdPercent) / 100)
    : 0;

  // Count-based requirement (or 0 if not set)
  const countRequired = thresholdCount ?? 0;

  // Return the MAX (more restrictive)
  return Math.max(percentRequired, countRequired);
}

/**
 * Check if auto-advance thresholds are met.
 *
 * @param config - The threshold configuration
 * @param data - Current participation data
 * @returns true if thresholds are met and phase should advance early
 */
export function shouldAutoAdvance(
  config: ThresholdConfig,
  data: ParticipationData
): boolean {
  const required = calculateRequiredCount(config, data.totalParticipants);

  // If auto-advance is disabled, don't advance
  if (required === null) {
    return false;
  }

  // Check if participation meets the requirement
  return data.participatedCount >= required;
}

/**
 * Check if rating auto-advance thresholds are met.
 * Caps the threshold to (participants - 1) since users can't rate their own propositions.
 *
 * @param config - The threshold configuration
 * @param data - Current participation data (participatedCount = avg ratings per proposition)
 * @returns true if thresholds are met and phase should advance early
 */
export function shouldAutoAdvanceRating(
  config: ThresholdConfig,
  data: ParticipationData
): boolean {
  const rawRequired = calculateRequiredCount(config, data.totalParticipants);

  // If auto-advance is disabled, don't advance
  if (rawRequired === null) {
    return false;
  }

  // Cap to what's maximally possible: (participants - 1)
  // Users can't rate their own propositions
  const maxPossible = Math.max(1, data.totalParticipants - 1);
  const effectiveRequired = Math.min(rawRequired, maxPossible);

  // Check if average ratings per proposition meets the requirement
  return data.participatedCount >= effectiveRequired;
}

/**
 * Calculate the effective rating threshold, capped to what's achievable.
 *
 * @param config - The threshold configuration
 * @param totalParticipants - Total active participants
 * @returns The effective required count, capped to (participants - 1)
 */
export function calculateRatingThresholdCapped(
  config: ThresholdConfig,
  totalParticipants: number
): number | null {
  const rawRequired = calculateRequiredCount(config, totalParticipants);

  if (rawRequired === null) {
    return null;
  }

  // Cap to what's maximally possible
  const maxPossible = Math.max(1, totalParticipants - 1);
  return Math.min(rawRequired, maxPossible);
}

/**
 * Get a human-readable explanation of the threshold calculation.
 * Useful for debugging and logging.
 */
export function explainThreshold(
  config: ThresholdConfig,
  totalParticipants: number
): string {
  const { thresholdPercent, thresholdCount } = config;

  if (thresholdPercent === null && thresholdCount === null) {
    return "Auto-advance disabled (no thresholds set)";
  }

  const percentRequired = thresholdPercent !== null
    ? Math.ceil((totalParticipants * thresholdPercent) / 100)
    : 0;
  const countRequired = thresholdCount ?? 0;
  const required = Math.max(percentRequired, countRequired);

  const parts: string[] = [];
  if (thresholdPercent !== null) {
    parts.push(`${thresholdPercent}% of ${totalParticipants} = ${percentRequired}`);
  }
  if (thresholdCount !== null) {
    parts.push(`count threshold = ${countRequired}`);
  }

  return `MAX(${parts.join(", ")}) = ${required} required`;
}

/**
 * Check if auto-advance thresholds are met with skip support.
 *
 * For proposing phase with skips:
 * - Participation check: (submitters + skippers) >= percent requirement
 * - Count check: submitters >= MIN(count_threshold, max_possible)
 *   where max_possible = total_participants - skip_count
 *
 * @param config - The threshold configuration
 * @param data - Current participation data including skip counts
 * @returns true if thresholds are met and phase should advance early
 */
export function shouldAutoAdvanceWithSkips(
  config: ThresholdConfig,
  data: SkipAwareParticipationData
): boolean {
  const { thresholdPercent, thresholdCount } = config;

  // If auto-advance is disabled, don't advance
  if (thresholdPercent === null && thresholdCount === null) {
    return false;
  }

  const { totalParticipants, skipCount, submitterCount } = data;
  const participatedCount = submitterCount + skipCount;
  const maxPossible = totalParticipants - skipCount;

  // Calculate percent-based requirement
  const percentRequired = thresholdPercent !== null
    ? Math.ceil((totalParticipants * thresholdPercent) / 100)
    : 0;

  // Calculate effective count threshold with dynamic adjustment
  const effectiveCountThreshold = thresholdCount !== null
    ? Math.min(thresholdCount, maxPossible)
    : 0;

  // Both conditions must be met:
  // 1. Participated (submitters + skippers) >= percent requirement
  // 2. Submitters >= effective count threshold
  const percentMet = participatedCount >= percentRequired;
  const countMet = submitterCount >= effectiveCountThreshold;

  return percentMet && countMet;
}

/**
 * Calculate how many skips are still allowed for a round.
 *
 * @param totalParticipants - Total active participants
 * @param currentSkipCount - Current number of skips
 * @param proposingMinimum - Minimum propositions required
 * @returns Number of additional skips allowed
 */
export function calculateRemainingSkips(
  totalParticipants: number,
  currentSkipCount: number,
  proposingMinimum: number
): number {
  // Max skips = total_participants - proposing_minimum
  const maxSkips = Math.max(0, totalParticipants - proposingMinimum);
  return Math.max(0, maxSkips - currentSkipCount);
}
