// k6 environment configuration
// Usage: export SUPABASE_URL and SUPABASE_ANON_KEY before running

export const SUPABASE_URL = __ENV.SUPABASE_URL || "https://ccyuxrtrklgpkzcryzpj.supabase.co";
export const SUPABASE_ANON_KEY = __ENV.SUPABASE_ANON_KEY || "";

// Derived URLs
export const AUTH_URL = `${SUPABASE_URL}/auth/v1`;
export const REST_URL = `${SUPABASE_URL}/rest/v1`;
export const FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;
export const REALTIME_URL = SUPABASE_URL.replace("https://", "wss://") + "/realtime/v1/websocket";

// Test data prefix — all test data uses this for easy cleanup
export const TEST_PREFIX = "k6_loadtest_";

// Default headers for all requests
export function baseHeaders(token) {
  const headers = {
    "Content-Type": "application/json",
    apikey: SUPABASE_ANON_KEY,
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }
  return headers;
}

// Common thresholds reused across scenarios
export const COMMON_THRESHOLDS = {
  "http_req_failed": ["rate<0.05"],              // <5% error rate
  "http_req_duration": ["p(95)<3000", "p(99)<8000"], // p95 < 3s, p99 < 8s
  "http_req_duration{name:signup}": ["p(95)<2000"],
  "http_req_duration{name:create_chat}": ["p(95)<3000"],
  "http_req_duration{name:submit_proposition}": ["p(95)<5000"],
  "http_req_duration{name:dashboard}": ["p(95)<3000"],
};
