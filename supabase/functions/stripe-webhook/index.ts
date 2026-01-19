// Edge Function: stripe-webhook
// Handles Stripe webhook events for payment confirmations
//
// Events handled:
//   - checkout.session.completed: Add credits to user account
//
// Idempotency:
//   - Uses UNIQUE constraint on stripe_checkout_session_id
//   - Safe against duplicate webhook deliveries and race conditions

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "npm:stripe@14";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY")!;
const stripeWebhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

// Timeout for Stripe API calls (30 seconds)
const STRIPE_TIMEOUT = 30000;

interface WebhookResult {
  success: boolean;
  status: "success" | "error" | "duplicate";
  message: string;
  eventId?: string;
  eventType?: string;
}

Deno.serve(async (req: Request) => {
  const startTime = Date.now();

  try {
    // Only accept POST requests
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    // Get the raw body for signature verification
    const body = await req.text();
    const signature = req.headers.get("stripe-signature");

    if (!signature) {
      return new Response("Missing stripe-signature header", { status: 400 });
    }

    // Initialize Stripe with timeout
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16",
      timeout: STRIPE_TIMEOUT,
    });

    // Verify webhook signature
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(body, signature, stripeWebhookSecret);
    } catch (err) {
      console.error("Webhook signature verification failed:", err);
      return new Response(
        JSON.stringify({
          error: "Webhook signature verification failed",
          code: "INVALID_SIGNATURE",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // Create Supabase client with service role (admin access)
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Process the event
    const result = await processWebhookEvent(supabase, event);

    // Log the event
    await logWebhookEvent(supabase, event, result);

    const duration = Date.now() - startTime;
    console.log(
      `[Webhook] ${event.type} (${event.id}) - ${result.status} in ${duration}ms`
    );

    if (!result.success && result.status !== "duplicate") {
      return new Response(JSON.stringify({ error: result.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ status: result.status }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Webhook error:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});

async function processWebhookEvent(
  supabase: ReturnType<typeof createClient>,
  event: Stripe.Event
): Promise<WebhookResult> {
  switch (event.type) {
    case "checkout.session.completed":
      return handleCheckoutCompleted(supabase, event);

    case "checkout.session.expired":
      // Session expired before completion - no action needed
      console.log("Checkout session expired:", event.data.object.id);
      return {
        success: true,
        status: "success",
        message: "Session expiration acknowledged",
        eventId: event.id,
        eventType: event.type,
      };

    default:
      // Unexpected event type - acknowledge but log
      console.log(`Unhandled event type: ${event.type}`);
      return {
        success: true,
        status: "success",
        message: `Unhandled event type: ${event.type}`,
        eventId: event.id,
        eventType: event.type,
      };
  }
}

async function handleCheckoutCompleted(
  supabase: ReturnType<typeof createClient>,
  event: Stripe.Event
): Promise<WebhookResult> {
  const session = event.data.object as Stripe.Checkout.Session;

  // Validate metadata
  const userId = session.metadata?.user_id;
  const creditsStr = session.metadata?.credits;

  if (!userId || !creditsStr) {
    console.error("Missing metadata in checkout session:", session.id);
    return {
      success: false,
      status: "error",
      message: `Missing metadata: user_id=${userId}, credits=${creditsStr}`,
      eventId: event.id,
      eventType: event.type,
    };
  }

  const credits = parseInt(creditsStr);
  if (isNaN(credits) || credits <= 0) {
    console.error("Invalid credits in metadata:", creditsStr);
    return {
      success: false,
      status: "error",
      message: `Invalid credits value: ${creditsStr}`,
      eventId: event.id,
      eventType: event.type,
    };
  }

  // Add credits using the improved database function
  // This function handles idempotency via UNIQUE constraint
  const { data, error } = await supabase.rpc("add_purchased_credits", {
    p_user_id: userId,
    p_credit_amount: credits,
    p_stripe_checkout_session_id: session.id,
    p_stripe_payment_intent_id: session.payment_intent as string | null,
    p_stripe_event_id: event.id,
  });

  if (error) {
    // Check if this is a duplicate (idempotency)
    if (error.code === "23505" || error.message?.includes("unique")) {
      console.log("Session already processed (unique constraint):", session.id);
      return {
        success: true,
        status: "duplicate",
        message: "Session already processed",
        eventId: event.id,
        eventType: event.type,
      };
    }

    console.error("Error adding credits:", error);
    return {
      success: false,
      status: "error",
      message: `Database error: ${error.message}`,
      eventId: event.id,
      eventType: event.type,
    };
  }

  console.log(
    `Successfully added ${credits} credits to user ${userId}. New balance: ${data?.credit_balance}`
  );

  return {
    success: true,
    status: "success",
    message: `Added ${credits} credits`,
    eventId: event.id,
    eventType: event.type,
  };
}

async function logWebhookEvent(
  supabase: ReturnType<typeof createClient>,
  event: Stripe.Event,
  result: WebhookResult
): Promise<void> {
  try {
    await supabase.rpc("log_stripe_webhook_event", {
      p_event_id: event.id,
      p_event_type: event.type,
      p_status: result.status,
      p_error_message: result.success ? null : result.message,
      p_metadata: {
        livemode: event.livemode,
        api_version: event.api_version,
        created: event.created,
      },
    });
  } catch (err) {
    // Don't let logging failures break webhook processing
    console.error("Failed to log webhook event:", err);
  }
}
