/**
 * Rate Limiter for Supabase Edge Functions
 *
 * Uses database-backed rate limiting with sliding windows.
 *
 * Usage:
 * ```typescript
 * import { RateLimiter } from "../_shared/rate-limiter.ts";
 *
 * const limiter = new RateLimiter(supabase);
 *
 * // Check rate limit before processing request
 * const { allowed, remaining, resetAt } = await limiter.check({
 *   key: `checkout:${userId}`,
 *   maxRequests: 10,
 *   windowSeconds: 60, // 10 requests per minute
 * });
 *
 * if (!allowed) {
 *   return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
 *     status: 429,
 *     headers: {
 *       "Retry-After": Math.ceil((resetAt - Date.now()) / 1000).toString(),
 *     },
 *   });
 * }
 * ```
 */

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface RateLimitConfig {
  /** Unique key for this rate limit (e.g., "checkout:user_123") */
  key: string;
  /** Maximum number of requests allowed in the window */
  maxRequests: number;
  /** Window size in seconds */
  windowSeconds: number;
}

export interface RateLimitResult {
  /** Whether the request is allowed */
  allowed: boolean;
  /** Remaining requests in current window */
  remaining: number;
  /** Unix timestamp when the rate limit resets */
  resetAt: number;
  /** Total requests in current window */
  current: number;
}

export class RateLimiter {
  private supabase: SupabaseClient;

  constructor(supabaseClient: SupabaseClient) {
    this.supabase = supabaseClient;
  }

  /**
   * Check and increment rate limit counter.
   * Returns whether the request is allowed.
   */
  async check(config: RateLimitConfig): Promise<RateLimitResult> {
    const { key, maxRequests, windowSeconds } = config;
    const windowInterval = `${windowSeconds} seconds`;

    try {
      // Call the database function to check rate limit
      const { data, error } = await this.supabase.rpc("check_rate_limit", {
        p_key: key,
        p_max_requests: maxRequests,
        p_window_size: windowInterval,
      });

      if (error) {
        console.error("[RateLimiter] Error checking rate limit:", error);
        // On error, allow the request (fail open) but log it
        return {
          allowed: true,
          remaining: maxRequests - 1,
          resetAt: Date.now() + windowSeconds * 1000,
          current: 1,
        };
      }

      const allowed = data === true;

      // Get current count for accurate remaining calculation
      const status = await this.getStatus(key, windowSeconds);

      return {
        allowed,
        remaining: Math.max(0, maxRequests - status.current),
        resetAt: status.resetAt,
        current: status.current,
      };
    } catch (err) {
      console.error("[RateLimiter] Unexpected error:", err);
      // Fail open on unexpected errors
      return {
        allowed: true,
        remaining: maxRequests - 1,
        resetAt: Date.now() + windowSeconds * 1000,
        current: 1,
      };
    }
  }

  /**
   * Get current rate limit status without incrementing counter.
   */
  async getStatus(
    key: string,
    windowSeconds: number
  ): Promise<{ current: number; resetAt: number }> {
    const windowInterval = `${windowSeconds} seconds`;

    try {
      const { data, error } = await this.supabase.rpc("get_rate_limit_status", {
        p_key: key,
        p_window_size: windowInterval,
      });

      if (error || !data || data.length === 0) {
        return {
          current: 0,
          resetAt: Date.now() + windowSeconds * 1000,
        };
      }

      const windowStart = new Date(data[0].window_start).getTime();
      const resetAt = windowStart + windowSeconds * 1000;

      return {
        current: data[0].current_count || 0,
        resetAt,
      };
    } catch {
      return {
        current: 0,
        resetAt: Date.now() + windowSeconds * 1000,
      };
    }
  }
}

/**
 * Predefined rate limit configurations for common use cases.
 */
export const RateLimitPresets = {
  /** 10 requests per minute - for checkout/payment endpoints */
  checkout: { maxRequests: 10, windowSeconds: 60 },

  /** 100 requests per minute - for standard API endpoints */
  standard: { maxRequests: 100, windowSeconds: 60 },

  /** 1000 requests per minute - for high-volume endpoints */
  highVolume: { maxRequests: 1000, windowSeconds: 60 },

  /** 5 requests per hour - for sensitive operations like password reset */
  sensitive: { maxRequests: 5, windowSeconds: 3600 },

  /** 1 request per second - for burst protection */
  burst: { maxRequests: 1, windowSeconds: 1 },
} as const;

/**
 * Create rate limit error response with proper headers.
 */
export function rateLimitResponse(
  result: RateLimitResult,
  corsHeaders: Record<string, string> = {}
): Response {
  const retryAfter = Math.ceil((result.resetAt - Date.now()) / 1000);

  return new Response(
    JSON.stringify({
      error: "Too many requests",
      code: "RATE_LIMITED",
      retryAfter,
      limit: {
        remaining: result.remaining,
        resetAt: new Date(result.resetAt).toISOString(),
      },
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": retryAfter.toString(),
        "X-RateLimit-Remaining": result.remaining.toString(),
        "X-RateLimit-Reset": result.resetAt.toString(),
      },
    }
  );
}
