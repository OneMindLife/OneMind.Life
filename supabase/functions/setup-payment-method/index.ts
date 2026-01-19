// Edge Function: setup-payment-method
// Creates a Stripe SetupIntent for saving a payment method for auto-refill
//
// Returns:
//   { "clientSecret": string, "customerId": string }
//   - clientSecret: Use with Stripe.js to complete setup
//   - customerId: Stripe customer ID

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
      key: `setup-payment:${user.id}`,
      ...RateLimitPresets.checkout,
    });

    if (!rateLimit.allowed) {
      return rateLimitResponse(rateLimit, corsHeaders);
    }

    // Initialize Stripe
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16",
    });

    // Check if user already has a Stripe customer ID
    const { data: userCredits } = await supabase
      .from("user_credits")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .maybeSingle();

    let customerId = userCredits?.stripe_customer_id;

    // Create Stripe customer if doesn't exist
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: {
          supabase_user_id: user.id,
        },
      });
      customerId = customer.id;

      // Save customer ID to database
      await supabase.rpc("get_or_create_user_credits", {
        p_user_id: user.id,
      });

      await supabase
        .from("user_credits")
        .update({ stripe_customer_id: customerId })
        .eq("user_id", user.id);
    }

    // Create SetupIntent for saving payment method
    const setupIntent = await stripe.setupIntents.create({
      customer: customerId,
      payment_method_types: ["card"],
      metadata: {
        supabase_user_id: user.id,
      },
    });

    return new Response(
      JSON.stringify({
        clientSecret: setupIntent.client_secret,
        customerId: customerId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error creating setup intent:", error);

    return corsErrorResponse(
      "Failed to create setup intent",
      req,
      500,
      "SETUP_ERROR"
    );
  }
});
