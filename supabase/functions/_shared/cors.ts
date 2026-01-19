/**
 * CORS & Security Headers for Supabase Edge Functions
 *
 * Provides:
 * - CORS headers with configurable allowed origins
 * - Security headers (XSS, clickjacking, MIME sniffing protection)
 *
 * Environment variables:
 * - ALLOWED_ORIGINS: Comma-separated list of allowed origins
 *   Set in Supabase dashboard under Edge Functions > Secrets:
 *   ALLOWED_ORIGINS=https://yourdomain.com,https://staging.yourdomain.com
 */

// Get allowed origins from environment or use localhost defaults
const allowedOriginsEnv = Deno.env.get("ALLOWED_ORIGINS") ?? "";
const allowedOrigins = allowedOriginsEnv
  ? allowedOriginsEnv.split(",").map((o) => o.trim())
  : [
      "http://localhost:3000",
      "http://localhost:8080",
      "http://127.0.0.1:3000",
      "http://127.0.0.1:8080",
    ];

/**
 * Security headers to protect against common web vulnerabilities.
 * These are included in all responses.
 */
const securityHeaders: Record<string, string> = {
  // Prevent MIME type sniffing - browser must trust Content-Type
  "X-Content-Type-Options": "nosniff",

  // Prevent clickjacking - don't allow site in iframes
  "X-Frame-Options": "DENY",

  // Force HTTPS for 1 year (31536000 seconds)
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",

  // XSS protection (legacy, but still useful for older browsers)
  "X-XSS-Protection": "1; mode=block",

  // Don't send referrer to other origins
  "Referrer-Policy": "strict-origin-when-cross-origin",

  // Restrict permissions (camera, microphone, etc.)
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};

/**
 * Check if an origin is allowed
 */
function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return false;

  // In development, allow all localhost origins
  if (
    origin.startsWith("http://localhost:") ||
    origin.startsWith("http://127.0.0.1:")
  ) {
    return Deno.env.get("ALLOWED_ORIGINS") === undefined;
  }

  return allowedOrigins.includes(origin);
}

/**
 * Get CORS and security headers for a request.
 * Returns appropriate headers based on the request origin.
 *
 * @param request - The incoming request
 * @returns CORS + security headers object
 */
export function getCorsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get("Origin");

  // If origin is allowed, reflect it back; otherwise, return first allowed origin
  const allowedOrigin = isAllowedOrigin(origin)
    ? origin!
    : allowedOrigins[0] ?? "*";

  return {
    // CORS headers
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Max-Age": "86400", // 24 hours
    // Security headers
    ...securityHeaders,
  };
}

/**
 * Handle CORS preflight (OPTIONS) request.
 *
 * @param request - The incoming request
 * @returns Response with CORS headers
 */
export function handleCorsPreFlight(request: Request): Response {
  return new Response("ok", {
    headers: getCorsHeaders(request),
  });
}

/**
 * Create a JSON response with CORS headers.
 *
 * @param data - Response body data
 * @param request - The original request (for CORS origin matching)
 * @param status - HTTP status code (default: 200)
 * @returns Response with CORS headers
 */
export function corsJsonResponse(
  data: unknown,
  request: Request,
  status = 200
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...getCorsHeaders(request),
      "Content-Type": "application/json",
    },
  });
}

/**
 * Create an error response with CORS headers.
 *
 * @param error - Error message
 * @param request - The original request
 * @param status - HTTP status code (default: 400)
 * @param code - Error code for client handling
 * @returns Error response with CORS headers
 */
export function corsErrorResponse(
  error: string,
  request: Request,
  status = 400,
  code?: string
): Response {
  return corsJsonResponse(
    { error, ...(code && { code }) },
    request,
    status
  );
}

// Export for use in rate limiter and other shared utilities
export { allowedOrigins, securityHeaders };
