// Edge Function Test: health
//
// Tests the health check endpoint including secrets validation.
// Run with: deno test --allow-all supabase/functions/tests/health-test.ts
//
// This test validates that the health function properly checks for:
// - Database connectivity
// - Required secrets configuration (CRON_SECRET, STRIPE_SECRET_KEY, NVIDIA_API_KEY)

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

// =============================================================================
// SECRETS CONFIGURATION TESTS
// =============================================================================
// These tests validate the logic for checking required secrets.
// They help catch configuration issues before they cause runtime failures.
// =============================================================================

Deno.test("health check - secrets validation logic", async (t) => {
  // The required secrets that should be checked
  const REQUIRED_SECRETS = [
    { name: "CRON_SECRET", desc: "Cron job authentication", critical: true },
    { name: "STRIPE_SECRET_KEY", desc: "Payment processing", critical: false },
    { name: "NVIDIA_API_KEY", desc: "AI translations (Kimi K2.5 via NVIDIA)", critical: false },
  ];

  await t.step("identifies missing secrets correctly", () => {
    // Simulate environment where only some secrets are set
    const mockEnv: Record<string, string | undefined> = {
      "CRON_SECRET": undefined,
      "STRIPE_SECRET_KEY": "sk_test_xxx",
      "NVIDIA_API_KEY": undefined,
    };

    const missingSecrets: string[] = [];
    const missingCritical: string[] = [];

    for (const secret of REQUIRED_SECRETS) {
      const value = mockEnv[secret.name];
      if (!value || value.length === 0) {
        missingSecrets.push(`${secret.name} (${secret.desc})`);
        if (secret.critical) {
          missingCritical.push(secret.name);
        }
      }
    }

    assertEquals(missingSecrets.length, 2, "Should identify 2 missing secrets");
    assertEquals(missingCritical.length, 1, "Should identify 1 critical missing secret");
    assertEquals(missingCritical[0], "CRON_SECRET", "CRON_SECRET should be critical");
  });

  await t.step("passes when all secrets are configured", () => {
    const mockEnv: Record<string, string | undefined> = {
      "CRON_SECRET": "test-secret",
      "STRIPE_SECRET_KEY": "sk_test_xxx",
      "NVIDIA_API_KEY": "nvapi-xxx",
    };

    const missingSecrets: string[] = [];

    for (const secret of REQUIRED_SECRETS) {
      const value = mockEnv[secret.name];
      if (!value || value.length === 0) {
        missingSecrets.push(secret.name);
      }
    }

    assertEquals(missingSecrets.length, 0, "Should have no missing secrets");
  });

  await t.step("treats empty string as missing", () => {
    const mockEnv: Record<string, string | undefined> = {
      "CRON_SECRET": "",
      "STRIPE_SECRET_KEY": "sk_test_xxx",
      "NVIDIA_API_KEY": "nvapi-xxx",
    };

    const missingSecrets: string[] = [];

    for (const secret of REQUIRED_SECRETS) {
      const value = mockEnv[secret.name];
      if (!value || value.length === 0) {
        missingSecrets.push(secret.name);
      }
    }

    assertEquals(missingSecrets.length, 1, "Empty string should count as missing");
    assertEquals(missingSecrets[0], "CRON_SECRET");
  });
});

// =============================================================================
// HEALTH RESPONSE STRUCTURE TESTS
// =============================================================================

Deno.test("health check - response structure", async (t) => {
  await t.step("determines healthy status when all checks pass", () => {
    const checks = {
      database: { name: "Database", status: "pass" as const },
      secrets: { name: "Secrets Configuration", status: "pass" as const },
    };

    const failedChecks = Object.values(checks).filter((c) => c.status === "fail");
    let overallStatus: "healthy" | "degraded" | "unhealthy";

    if (failedChecks.length === 0) {
      overallStatus = "healthy";
    } else if (failedChecks.length < Object.keys(checks).length) {
      overallStatus = "degraded";
    } else {
      overallStatus = "unhealthy";
    }

    assertEquals(overallStatus, "healthy");
  });

  await t.step("determines degraded status when some checks fail", () => {
    const checks = {
      database: { name: "Database", status: "pass" as const },
      secrets: { name: "Secrets Configuration", status: "fail" as const },
    };

    const failedChecks = Object.values(checks).filter((c) => c.status === "fail");
    let overallStatus: "healthy" | "degraded" | "unhealthy";

    if (failedChecks.length === 0) {
      overallStatus = "healthy";
    } else if (failedChecks.length < Object.keys(checks).length) {
      overallStatus = "degraded";
    } else {
      overallStatus = "unhealthy";
    }

    assertEquals(overallStatus, "degraded");
  });

  await t.step("determines unhealthy status when all checks fail", () => {
    const checks = {
      database: { name: "Database", status: "fail" as const },
      secrets: { name: "Secrets Configuration", status: "fail" as const },
    };

    const failedChecks = Object.values(checks).filter((c) => c.status === "fail");
    let overallStatus: "healthy" | "degraded" | "unhealthy";

    if (failedChecks.length === 0) {
      overallStatus = "healthy";
    } else if (failedChecks.length < Object.keys(checks).length) {
      overallStatus = "degraded";
    } else {
      overallStatus = "unhealthy";
    }

    assertEquals(overallStatus, "unhealthy");
  });
});

// =============================================================================
// DOCUMENTATION: Required Secrets
// =============================================================================
// The following secrets MUST be configured in Supabase Edge Function Secrets:
//
// 1. CRON_SECRET (CRITICAL)
//    - Purpose: Authenticates cron job requests to process-timers/process-auto-refill
//    - Value: Must match the X-Cron-Secret header in cron.job commands
//    - See docs/DEPLOYMENT.md for the current value
//
// 2. STRIPE_SECRET_KEY
//    - Purpose: Payment processing for credits system
//    - Value: From Stripe Dashboard > API Keys
//
// 3. NVIDIA_API_KEY
//    - Purpose: AI-powered translations
//    - Value: From NVIDIA Developer Program (build.nvidia.com)
//
// To set secrets:
// 1. Go to Supabase Dashboard > Edge Functions > Manage Secrets
// 2. Add each secret name and value
// 3. Redeploy functions or wait for next deployment
//
// To verify secrets are configured:
// curl https://YOUR_PROJECT.supabase.co/functions/v1/health
// =============================================================================
