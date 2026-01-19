// Edge Function: create-checkout-session
// Creates a Stripe Checkout session for purchasing credits
//
// Request body:
//   { "credits": number } - Number of credits to purchase (1 credit = $0.01)
//
// Returns:
//   { "url": string } - Stripe Checkout URL to redirect user to
//
// Rate Limits:
//   - 10 requests per minute per user

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "npm:stripe@14";
import {
  RateLimiter,
  RateLimitPresets,
  rateLimitResponse,
} from "../_shared/rate-limiter.ts";
import {
  getCorsHeaders,
  handleCorsPreFlight,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  validateInteger,
  formatValidationErrors,
} from "../_shared/validation.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY")!;

// Stripe Price ID for OneMind Credit ($0.01 per unit)
// Must be set in Supabase secrets - use test price for dev, live price for production
const STRIPE_CREDIT_PRICE_ID = Deno.env.get("STRIPE_CREDIT_PRICE_ID");

if (!STRIPE_CREDIT_PRICE_ID) {
  console.error("STRIPE_CREDIT_PRICE_ID environment variable is required");
}

// Minimum and maximum credits per purchase
const MIN_CREDITS = 1;
const MAX_CREDITS = 100000; // $1000 max per transaction

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

    // Create Supabase client with service role for rate limiting
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // Create Supabase client with user's JWT for user operations
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      global: {
        headers: { Authorization: authHeader },
      },
    });

    // Get user from JWT
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (userError || !user) {
      return corsErrorResponse("Invalid or expired token", req, 401);
    }

    // Check rate limit
    const rateLimiter = new RateLimiter(supabaseAdmin);
    const rateLimit = await rateLimiter.check({
      key: `checkout:${user.id}`,
      ...RateLimitPresets.checkout,
    });

    if (!rateLimit.allowed) {
      console.log(
        `[RateLimit] User ${user.id} exceeded checkout rate limit. Current: ${rateLimit.current}`
      );
      return rateLimitResponse(rateLimit, corsHeaders);
    }

    // Parse and validate request body
    let body: { credits?: unknown };
    try {
      body = await req.json();
    } catch {
      return corsErrorResponse("Invalid JSON body", req, 400, "INVALID_JSON");
    }

    // Server-side validation
    const creditsValidation = validateInteger(body.credits, "credits", {
      required: true,
      min: MIN_CREDITS,
      max: MAX_CREDITS,
    });

    if (!creditsValidation.valid) {
      return corsErrorResponse(
        formatValidationErrors(creditsValidation.errors),
        req,
        400,
        "VALIDATION_ERROR"
      );
    }

    const credits = parseInt(String(body.credits));

    // Verify price ID is configured
    if (!STRIPE_CREDIT_PRICE_ID) {
      console.error("STRIPE_CREDIT_PRICE_ID not configured");
      return corsErrorResponse(
        "Payment system not configured",
        req,
        500,
        "CONFIG_ERROR"
      );
    }

    // Initialize Stripe
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16",
    });

    // Get the origin for success/cancel URLs
    const origin = req.headers.get("origin") || "http://localhost:3000";

    // Create Stripe Checkout session with pre-defined price
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      line_items: [
        {
          price: STRIPE_CREDIT_PRICE_ID,
          quantity: credits,
        },
      ],
      mode: "payment",
      success_url: `${origin}/credits/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${origin}/credits/cancel`,
      metadata: {
        user_id: user.id,
        credits: credits.toString(),
      },
      customer_email: user.email,
    });

    return new Response(JSON.stringify({ url: session.url }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Error creating checkout session:", error);

    return corsErrorResponse(
      "Failed to create checkout session",
      req,
      500,
      "CHECKOUT_ERROR"
    );
  }
});
