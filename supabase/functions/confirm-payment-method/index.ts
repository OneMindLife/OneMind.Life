// Edge Function: confirm-payment-method
// Confirms and saves a payment method after SetupIntent completion
//
// Request body:
//   { "setupIntentId": string }
//
// Returns:
//   { "success": true, "paymentMethod": { last4, brand, expMonth, expYear } }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "npm:stripe@14";
import {
  getCorsHeaders,
  handleCorsPreFlight,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  RateLimiter,
  RateLimitPresets,
  rateLimitResponse,
} from "../_shared/rate-limiter.ts";
import {
  validateStripeId,
  formatValidationErrors,
} from "../_shared/validation.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY")!;

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  const corsHeaders = getCorsHeaders(req);

  try {
    // Verify user is authenticated
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return corsErrorResponse("Missing authorization header", req, 401);
    }

    // Create Supabase client
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Get user from JWT
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (userError || !user) {
      return corsErrorResponse("Invalid or expired token", req, 401);
    }

    // Check rate limit (10 requests per minute per user)
    const limiter = new RateLimiter(supabase);
    const rateLimit = await limiter.check({
      key: `confirm-payment:${user.id}`,
      ...RateLimitPresets.checkout,
    });

    if (!rateLimit.allowed) {
      return rateLimitResponse(rateLimit, corsHeaders);
    }

    // Parse and validate request body
    let body: { setupIntentId?: unknown };
    try {
      body = await req.json();
    } catch {
      return corsErrorResponse("Invalid JSON body", req, 400, "INVALID_JSON");
    }

    // Server-side validation - SetupIntent IDs start with "seti_"
    const setupIntentValidation = validateStripeId(
      body.setupIntentId,
      "setupIntentId",
      "seti_"
    );

    if (!setupIntentValidation.valid) {
      return corsErrorResponse(
        formatValidationErrors(setupIntentValidation.errors),
        req,
        400,
        "VALIDATION_ERROR"
      );
    }

    const setupIntentId = body.setupIntentId as string;

    // Initialize Stripe
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16",
    });

    // Retrieve the SetupIntent
    const setupIntent = await stripe.setupIntents.retrieve(setupIntentId);

    // Verify the SetupIntent belongs to this user
    if (setupIntent.metadata?.supabase_user_id !== user.id) {
      return corsErrorResponse(
        "SetupIntent does not belong to this user",
        req,
        403
      );
    }

    // Check SetupIntent status
    if (setupIntent.status !== "succeeded") {
      return corsErrorResponse(
        `SetupIntent not successful. Status: ${setupIntent.status}`,
        req,
        400
      );
    }

    const paymentMethodId = setupIntent.payment_method as string;

    // Get payment method details
    const paymentMethod = await stripe.paymentMethods.retrieve(paymentMethodId);

    // Set as default payment method for customer
    await stripe.customers.update(setupIntent.customer as string, {
      invoice_settings: {
        default_payment_method: paymentMethodId,
      },
    });

    // Save to database
    await supabase.rpc("save_stripe_payment_method", {
      p_user_id: user.id,
      p_stripe_customer_id: setupIntent.customer as string,
      p_stripe_payment_method_id: paymentMethodId,
    });

    return new Response(
      JSON.stringify({
        success: true,
        paymentMethod: {
          id: paymentMethodId,
          last4: paymentMethod.card?.last4,
          brand: paymentMethod.card?.brand,
          expMonth: paymentMethod.card?.exp_month,
          expYear: paymentMethod.card?.exp_year,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error confirming payment method:", error);

    return corsErrorResponse(
      "Failed to confirm payment method",
      req,
      500,
      "CONFIRM_ERROR"
    );
  }
});
