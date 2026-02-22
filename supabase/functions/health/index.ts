// Edge Function: health
// Health check endpoint for monitoring and deployment verification
//
// Returns:
//   {
//     "status": "healthy" | "degraded" | "unhealthy",
//     "timestamp": ISO date string,
//     "version": app version,
//     "checks": { database: boolean, ... }
//   }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  getCorsHeaders,
  handleCorsPreFlight,
} from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// App version - update this when deploying new versions
const APP_VERSION = Deno.env.get("APP_VERSION") ?? "1.0.0";

// Required secrets for full functionality
// These are checked to catch configuration issues early
const REQUIRED_SECRETS = [
  { name: "CRON_SECRET", desc: "Cron job authentication", critical: true },
  { name: "STRIPE_SECRET_KEY", desc: "Payment processing", critical: false },
  { name: "NVIDIA_API_KEY", desc: "AI translations (Kimi K2.5 via NVIDIA)", critical: false },
] as const;

interface HealthCheck {
  name: string;
  status: "pass" | "fail";
  latencyMs?: number;
  message?: string;
}

interface HealthResponse {
  status: "healthy" | "degraded" | "unhealthy";
  timestamp: string;
  version: string;
  checks: Record<string, HealthCheck>;
}

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  const corsHeaders = getCorsHeaders(req);

  const checks: Record<string, HealthCheck> = {};

  // Database connectivity check
  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const start = Date.now();

    // Simple query to verify database connectivity
    const { error } = await supabase
      .from("chats")
      .select("id")
      .limit(1);

    const latencyMs = Date.now() - start;

    if (error) {
      checks.database = {
        name: "Database",
        status: "fail",
        latencyMs,
        message: error.message,
      };
    } else {
      checks.database = {
        name: "Database",
        status: "pass",
        latencyMs,
      };
    }
  } catch (error) {
    checks.database = {
      name: "Database",
      status: "fail",
      message: error instanceof Error ? error.message : "Unknown error",
    };
  }

  // Secrets configuration check
  // Validates that required environment variables are set
  const missingSecrets: string[] = [];
  const missingCritical: string[] = [];

  for (const secret of REQUIRED_SECRETS) {
    const value = Deno.env.get(secret.name);
    if (!value || value.length === 0) {
      missingSecrets.push(`${secret.name} (${secret.desc})`);
      if (secret.critical) {
        missingCritical.push(secret.name);
      }
    }
  }

  if (missingSecrets.length === 0) {
    checks.secrets = {
      name: "Secrets Configuration",
      status: "pass",
      message: `All ${REQUIRED_SECRETS.length} required secrets configured`,
    };
  } else {
    checks.secrets = {
      name: "Secrets Configuration",
      status: "fail",
      message: `Missing: ${missingSecrets.join(", ")}`,
    };
  }

  // Determine overall status
  const failedChecks = Object.values(checks).filter((c) => c.status === "fail");
  let overallStatus: "healthy" | "degraded" | "unhealthy";

  if (failedChecks.length === 0) {
    overallStatus = "healthy";
  } else if (failedChecks.length < Object.keys(checks).length) {
    overallStatus = "degraded";
  } else {
    overallStatus = "unhealthy";
  }

  const response: HealthResponse = {
    status: overallStatus,
    timestamp: new Date().toISOString(),
    version: APP_VERSION,
    checks,
  };

  // Return appropriate status code
  const statusCode = overallStatus === "healthy" ? 200 : 503;

  return new Response(JSON.stringify(response), {
    status: statusCode,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-cache, no-store, must-revalidate",
    },
  });
});
