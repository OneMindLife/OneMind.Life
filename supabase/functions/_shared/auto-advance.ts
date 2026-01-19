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
