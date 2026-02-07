// Edge Function: process-auto-refill
// Processes queued auto-refill requests by charging saved payment methods
// Should be called by a cron job every minute

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "npm:stripe@14";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY")!;

// Secret for cron job authentication (required - must be set in Supabase secrets)
const CRON_SECRET = Deno.env.get("CRON_SECRET");

if (!CRON_SECRET) {
  console.error("CRON_SECRET environment variable is required but not set");
}

// Price per credit in cents
const CREDIT_PRICE_CENTS = 1;

interface QueueItem {
  id: number;
  user_id: string;
  credits_to_add: number;
}

interface UserCredits {
  stripe_customer_id: string;
  stripe_payment_method_id: string;
}

interface ProcessResult {
  processed: number;
  succeeded: number;
  failed: number;
  errors: string[];
}

Deno.serve(async (req: Request) => {
  try {
    // Verify cron secret via X-Cron-Secret header or Authorization: Bearer
    const authHeader = req.headers.get("Authorization");
    const cronSecretHeader = req.headers.get("X-Cron-Secret");
    const isValidCron = CRON_SECRET && cronSecretHeader === CRON_SECRET;
    const isValidBearer = CRON_SECRET && authHeader === `Bearer ${CRON_SECRET}`;
    if (!isValidCron && !isValidBearer) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Create Supabase client with service role
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Initialize Stripe
    const stripe = new Stripe(stripeSecretKey, {
      apiVersion: "2023-10-16",
    });

    const result: ProcessResult = {
      processed: 0,
      succeeded: 0,
      failed: 0,
      errors: [],
    };

    // Get pending auto-refill requests (limit to 10 per run)
    const { data: queueItems, error: queueError } = await supabase
      .from("auto_refill_queue")
      .select("id, user_id, credits_to_add")
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(10);

    if (queueError) {
      throw new Error(`Failed to get queue: ${queueError.message}`);
    }

    if (!queueItems || queueItems.length === 0) {
      return new Response(
        JSON.stringify({ message: "No pending auto-refills", result }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    // Process each queue item
    for (const item of queueItems as QueueItem[]) {
      result.processed++;

      try {
        // Mark as processing
        await supabase
          .from("auto_refill_queue")
          .update({ status: "processing" })
          .eq("id", item.id);

        // Get user's Stripe info
        const { data: userCredits, error: creditsError } = await supabase
          .from("user_credits")
          .select("stripe_customer_id, stripe_payment_method_id")
          .eq("user_id", item.user_id)
          .single();

        if (creditsError || !userCredits) {
          throw new Error("User credits not found");
        }

        const credits = userCredits as UserCredits;

        if (!credits.stripe_customer_id || !credits.stripe_payment_method_id) {
          throw new Error("No payment method saved");
        }

        // Calculate amount
        const amountCents = item.credits_to_add * CREDIT_PRICE_CENTS;

        // Create PaymentIntent and charge immediately
        const paymentIntent = await stripe.paymentIntents.create({
          amount: amountCents,
          currency: "usd",
          customer: credits.stripe_customer_id,
          payment_method: credits.stripe_payment_method_id,
          off_session: true,
          confirm: true,
          description: `Auto-refill: ${item.credits_to_add} OneMind credits`,
          metadata: {
            supabase_user_id: item.user_id,
            credits: item.credits_to_add.toString(),
            type: "auto_refill",
          },
        });

        if (paymentIntent.status !== "succeeded") {
          throw new Error(`Payment failed: ${paymentIntent.status}`);
        }

        // Add credits to user account
        const { error: addError } = await supabase.rpc("add_purchased_credits", {
          p_user_id: item.user_id,
          p_credit_amount: item.credits_to_add,
          p_stripe_checkout_session_id: `auto_refill_${item.id}`,
          p_stripe_payment_intent_id: paymentIntent.id,
        });

        if (addError) {
          throw new Error(`Failed to add credits: ${addError.message}`);
        }

        // Update transaction type to auto_refill
        await supabase
          .from("credit_transactions")
          .update({
            transaction_type: "auto_refill",
            description: `Auto-refill: ${item.credits_to_add} credits`
          })
          .eq("stripe_payment_intent_id", paymentIntent.id);

        // Mark queue item as completed
        await supabase
          .from("auto_refill_queue")
          .update({
            status: "completed",
            stripe_payment_intent_id: paymentIntent.id,
            processed_at: new Date().toISOString(),
          })
          .eq("id", item.id);

        // Clear any previous error on user_credits
        await supabase
          .from("user_credits")
          .update({ auto_refill_last_error: null })
          .eq("user_id", item.user_id);

        result.succeeded++;
        console.log(
          `Auto-refill succeeded for user ${item.user_id}: ${item.credits_to_add} credits`
        );
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : "Unknown error";
        result.failed++;
        result.errors.push(`User ${item.user_id}: ${errorMessage}`);

        // Mark queue item as failed
        await supabase
          .from("auto_refill_queue")
          .update({
            status: "failed",
            error_message: errorMessage,
            processed_at: new Date().toISOString(),
          })
          .eq("id", item.id);

        // Record error on user_credits
        await supabase
          .from("user_credits")
          .update({ auto_refill_last_error: errorMessage })
          .eq("user_id", item.user_id);

        console.error(`Auto-refill failed for user ${item.user_id}:`, error);
      }
    }

    return new Response(JSON.stringify({ result }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Process auto-refill error:", error);

    return new Response(
      JSON.stringify({
        error: "Failed to process auto-refills",
        details: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
