// Edge Function: send-email
// Sends transactional emails (invites, receipts, welcome)
//
// Authentication:
//   - User JWT: Validated by Supabase Edge Runtime (automatic)
//   - Service Role: For internal/server-to-server calls
//   - Local Dev: Use --no-verify-jwt flag with supabase functions serve
//
// Request body:
//   { "type": "invite" | "receipt" | "welcome", "to": "email", ...params }
//
// Returns:
//   { "success": true, "id": "email_id" }
//
// Local Development:
//   npx supabase functions serve --env-file supabase/functions/.env --no-verify-jwt
//
// Required Environment Variables:
//   - RESEND_API_KEY: API key from resend.com
//   - SUPABASE_URL: Auto-provided by runtime
//   - SUPABASE_SERVICE_ROLE_KEY: Auto-provided by runtime

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  getCorsHeaders,
  handleCorsPreFlight,
  corsJsonResponse,
  corsErrorResponse,
} from "../_shared/cors.ts";
import {
  sendEmail,
  welcomeEmail,
  inviteEmail,
  paymentReceiptEmail,
} from "../_shared/email.ts";
import {
  RateLimiter,
  RateLimitPresets,
  rateLimitResponse,
} from "../_shared/rate-limiter.ts";
import {
  validateEmail,
  validateEnum,
  combineValidations,
  formatValidationErrors,
  sanitizeString,
  containsMaliciousContent,
} from "../_shared/validation.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type EmailType = "welcome" | "invite" | "receipt";

interface WelcomeRequest {
  type: "welcome";
  to: string;
  userName?: string;
}

interface InviteRequest {
  type: "invite";
  to: string;
  inviterName?: string;
  chatName: string;
  inviteToken?: string;  // UUID token for direct invite link
  inviteCode?: string;   // 6-char code for code-based access
  message?: string;
}

interface ReceiptRequest {
  type: "receipt";
  to: string;
  userName?: string;
  credits: number;
  amount: number;
  transactionId: string;
}

type EmailRequest = WelcomeRequest | InviteRequest | ReceiptRequest;

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return handleCorsPreFlight(req);
  }

  try {
    // Authentication is handled by Supabase Edge Runtime:
    // - Production: Runtime validates JWT automatically
    // - Local dev: Use --no-verify-jwt flag to bypass
    //
    // The Authorization header is required but validation is delegated to runtime.
    // This ensures consistent behavior between local and production environments.
    const authHeader = req.headers.get("Authorization");

    if (!authHeader) {
      return corsErrorResponse(
        "Missing authorization header. Include 'Authorization: Bearer <token>' with your request.",
        req,
        401,
        "AUTH_REQUIRED"
      );
    }

    // Note: JWT validation is handled by the Edge Runtime, not here.
    // In production, invalid tokens are rejected before reaching this code.
    // In local dev with --no-verify-jwt, tokens are not validated.

    // Parse request body
    let body: EmailRequest;
    try {
      body = await req.json();
    } catch {
      return corsErrorResponse("Invalid JSON body", req, 400, "INVALID_JSON");
    }

    // Server-side validation
    const EMAIL_TYPES = ["welcome", "invite", "receipt"] as const;
    const baseValidation = combineValidations(
      validateEnum(body.type, "type", EMAIL_TYPES),
      validateEmail(body.to, "to")
    );

    if (!baseValidation.valid) {
      return corsErrorResponse(
        formatValidationErrors(baseValidation.errors),
        req,
        400,
        "VALIDATION_ERROR"
      );
    }

    // Check for malicious content in string fields
    const stringFields = [body.userName, (body as InviteRequest).chatName, (body as InviteRequest).message];
    for (const field of stringFields) {
      if (field && containsMaliciousContent(field)) {
        return corsErrorResponse(
          "Request contains potentially malicious content",
          req,
          400,
          "MALICIOUS_CONTENT"
        );
      }
    }

    // Sanitize string inputs
    if (body.userName) body.userName = sanitizeString(body.userName);
    if ((body as InviteRequest).chatName) {
      (body as InviteRequest).chatName = sanitizeString((body as InviteRequest).chatName);
    }
    if ((body as InviteRequest).message) {
      (body as InviteRequest).message = sanitizeString((body as InviteRequest).message);
    }

    // Rate limit by recipient email (5 emails per hour per recipient)
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const limiter = new RateLimiter(supabase);
    const rateLimit = await limiter.check({
      key: `email:${body.to}`,
      ...RateLimitPresets.sensitive, // 5 requests per hour
    });

    if (!rateLimit.allowed) {
      return rateLimitResponse(rateLimit, getCorsHeaders(req));
    }

    // Generate email content based on type
    let emailContent: { subject: string; html: string; text: string };

    switch (body.type) {
      case "welcome":
        emailContent = welcomeEmail(body.userName);
        break;

      case "invite":
        // Require chatName and either inviteToken or inviteCode
        if (!body.chatName || (!body.inviteToken && !body.inviteCode)) {
          return corsErrorResponse(
            "Missing required fields for invite: chatName and (inviteToken or inviteCode)",
            req,
            400
          );
        }
        emailContent = inviteEmail({
          inviterName: body.inviterName,
          chatName: body.chatName,
          inviteToken: body.inviteToken,
          inviteCode: body.inviteCode,
          message: body.message,
        });
        break;

      case "receipt":
        if (
          body.credits === undefined ||
          body.amount === undefined ||
          !body.transactionId
        ) {
          return corsErrorResponse(
            "Missing required fields for receipt: credits, amount, transactionId",
            req,
            400
          );
        }
        emailContent = paymentReceiptEmail({
          userName: body.userName,
          credits: body.credits,
          amount: body.amount,
          transactionId: body.transactionId,
          date: new Date(),
        });
        break;

      default:
        return corsErrorResponse(
          `Invalid email type: ${(body as { type: string }).type}`,
          req,
          400
        );
    }

    // Send the email
    const result = await sendEmail({
      to: body.to,
      subject: emailContent.subject,
      html: emailContent.html,
      text: emailContent.text,
    });

    if (!result.success) {
      console.error("Email send failed:", result.error);
      return corsErrorResponse(
        result.error ?? "Failed to send email",
        req,
        500,
        "EMAIL_SEND_FAILED"
      );
    }

    return corsJsonResponse(
      {
        success: true,
        id: result.id,
        type: body.type,
      },
      req
    );
  } catch (error) {
    console.error("Send email error:", error);
    return corsErrorResponse(
      "Failed to process email request",
      req,
      500,
      "EMAIL_ERROR"
    );
  }
});
