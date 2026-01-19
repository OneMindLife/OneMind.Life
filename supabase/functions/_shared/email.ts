/**
 * Email Service for OneMind
 *
 * Uses Resend API for transactional emails.
 * Set RESEND_API_KEY in Supabase Edge Function secrets.
 *
 * To get an API key:
 * 1. Sign up at https://resend.com
 * 2. Create an API key
 * 3. Add to Supabase: supabase secrets set RESEND_API_KEY=re_xxxxx
 */

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") ?? "OneMind <hello@mail.YOUR_DOMAIN>";
const REPLY_TO_EMAIL = Deno.env.get("REPLY_TO_EMAIL") ?? "your-email@YOUR_DOMAIN";
const APP_URL = Deno.env.get("APP_URL") ?? "https://YOUR_DOMAIN";

export interface EmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

export interface EmailResult {
  success: boolean;
  id?: string;
  error?: string;
}

/**
 * Send an email using Resend API
 */
export async function sendEmail(options: EmailOptions): Promise<EmailResult> {
  if (!RESEND_API_KEY) {
    console.error("RESEND_API_KEY not configured");
    return { success: false, error: "Email service not configured" };
  }

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        reply_to: REPLY_TO_EMAIL,
        to: options.to,
        subject: options.subject,
        html: options.html,
        text: options.text,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error("Resend API error:", error);
      return { success: false, error: `Email API error: ${response.status}` };
    }

    const data = await response.json();
    return { success: true, id: data.id };
  } catch (error) {
    console.error("Email send error:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

// ============================================================
// Email Templates
// ============================================================

/**
 * Welcome email for new users
 */
export function welcomeEmail(userName?: string): { subject: string; html: string; text: string } {
  const name = userName ?? "there";

  return {
    subject: "Welcome to OneMind!",
    html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to OneMind</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="text-align: center; margin-bottom: 30px;">
    <h1 style="color: #6366F1; margin: 0;">OneMind</h1>
    <p style="color: #666; margin: 5px 0;">Find consensus together</p>
  </div>

  <h2 style="color: #333;">Welcome, ${name}!</h2>

  <p>Thanks for joining OneMind. You're now part of a community that makes better decisions together.</p>

  <h3 style="color: #6366F1;">How it works:</h3>
  <ol style="color: #555;">
    <li><strong>Create or join a chat</strong> - Start a discussion on any topic</li>
    <li><strong>Share your ideas</strong> - Submit propositions during the proposing phase</li>
    <li><strong>Rate proposals</strong> - Use our grid ranking to evaluate all ideas</li>
    <li><strong>Reach consensus</strong> - The best idea wins when everyone agrees</li>
  </ol>

  <div style="text-align: center; margin: 30px 0;">
    <a href="${APP_URL}" style="background-color: #6366F1; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; display: inline-block;">Get Started</a>
  </div>

  <p style="color: #666; font-size: 14px;">Questions? Just reply to this email.</p>

  <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">

  <p style="color: #999; font-size: 12px; text-align: center;">
    OneMind - Collective alignment platform<br>
    <a href="${APP_URL}" style="color: #6366F1;">YOUR_DOMAIN</a>
  </p>
</body>
</html>
    `.trim(),
    text: `
Welcome to OneMind, ${name}!

Thanks for joining OneMind. You're now part of a community that makes better decisions together.

How it works:
1. Create or join a chat - Start a discussion on any topic
2. Share your ideas - Submit propositions during the proposing phase
3. Rate proposals - Use our grid ranking to evaluate all ideas
4. Reach consensus - The best idea wins when everyone agrees

Get started: ${APP_URL}

Questions? Just reply to this email.

---
OneMind - Collective alignment platform
    `.trim(),
  };
}

/**
 * Chat invite email
 *
 * Supports two join methods:
 * - inviteToken: Direct link via /join/invite?token=xxx (for invite-only chats)
 * - inviteCode: Code-based join via /join/ABCDEF (for code access chats)
 */
export function inviteEmail(params: {
  inviterName?: string;
  chatName: string;
  inviteToken?: string;
  inviteCode?: string;
  message?: string;
}): { subject: string; html: string; text: string } {
  const { inviterName, chatName, inviteToken, inviteCode, message } = params;
  const inviter = inviterName ?? "Someone";

  // Prefer token-based link (works for all invite types)
  // Fall back to code-based link if no token provided
  const joinUrl = inviteToken
    ? `${APP_URL}/join/invite?token=${inviteToken}`
    : `${APP_URL}/join/${inviteCode}`;

  // Show invite code section only if code is provided
  const codeSection = inviteCode
    ? `<p style="color: #666; font-size: 14px;">Or use invite code: <strong>${inviteCode}</strong></p>`
    : "";
  const codeText = inviteCode ? `\nOr use invite code: ${inviteCode}` : "";

  return {
    subject: `You're invited to "${chatName}" on OneMind`,
    html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>You're Invited</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="text-align: center; margin-bottom: 30px;">
    <h1 style="color: #6366F1; margin: 0;">OneMind</h1>
    <p style="color: #666; margin: 5px 0;">Find consensus together</p>
  </div>

  <h2 style="color: #333;">You're invited!</h2>

  <p><strong>${inviter}</strong> wants you to join a discussion on OneMind:</p>

  <div style="background-color: #f8f9fa; border-radius: 8px; padding: 20px; margin: 20px 0;">
    <h3 style="color: #6366F1; margin: 0 0 10px 0;">${chatName}</h3>
    ${message ? `<p style="color: #666; margin: 0;">"${message}"</p>` : ""}
  </div>

  <div style="text-align: center; margin: 30px 0;">
    <a href="${joinUrl}" style="background-color: #6366F1; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; display: inline-block;">Join Discussion</a>
  </div>

  ${codeSection}

  <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">

  <p style="color: #999; font-size: 12px;">
    <strong>What is OneMind?</strong><br>
    OneMind helps groups reach consensus on any topic. Share ideas, rate proposals, and find the best answer together.
  </p>

  <p style="color: #999; font-size: 12px; text-align: center;">
    <a href="${APP_URL}" style="color: #6366F1;">YOUR_DOMAIN</a>
  </p>
</body>
</html>
    `.trim(),
    text: `
You're invited to OneMind!

${inviter} wants you to join a discussion:

"${chatName}"
${message ? `\n"${message}"\n` : ""}

Join here: ${joinUrl}
${codeText}

---
What is OneMind?
OneMind helps groups reach consensus on any topic. Share ideas, rate proposals, and find the best answer together.

onemind.app
    `.trim(),
  };
}

/**
 * Payment receipt email
 */
export function paymentReceiptEmail(params: {
  userName?: string;
  credits: number;
  amount: number;
  transactionId: string;
  date: Date;
}): { subject: string; html: string; text: string } {
  const { userName, credits, amount, transactionId, date } = params;
  const name = userName ?? "there";
  const formattedAmount = `$${amount.toFixed(2)}`;
  const formattedDate = date.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  return {
    subject: `Payment Receipt - ${credits} OneMind Credits`,
    html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Payment Receipt</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="text-align: center; margin-bottom: 30px;">
    <h1 style="color: #6366F1; margin: 0;">OneMind</h1>
    <p style="color: #666; margin: 5px 0;">Payment Receipt</p>
  </div>

  <p>Hi ${name},</p>

  <p>Thank you for your purchase! Here's your receipt:</p>

  <div style="background-color: #f8f9fa; border-radius: 8px; padding: 20px; margin: 20px 0;">
    <table style="width: 100%; border-collapse: collapse;">
      <tr>
        <td style="padding: 8px 0; color: #666;">Date</td>
        <td style="padding: 8px 0; text-align: right;">${formattedDate}</td>
      </tr>
      <tr>
        <td style="padding: 8px 0; color: #666;">Item</td>
        <td style="padding: 8px 0; text-align: right;">OneMind Credits</td>
      </tr>
      <tr>
        <td style="padding: 8px 0; color: #666;">Quantity</td>
        <td style="padding: 8px 0; text-align: right;">${credits} credits</td>
      </tr>
      <tr style="border-top: 1px solid #ddd;">
        <td style="padding: 12px 0 8px 0; color: #333; font-weight: bold;">Total</td>
        <td style="padding: 12px 0 8px 0; text-align: right; font-weight: bold; color: #6366F1;">${formattedAmount} USD</td>
      </tr>
    </table>
  </div>

  <p style="color: #666; font-size: 14px;">Transaction ID: ${transactionId}</p>

  <p>Your credits have been added to your account and are ready to use.</p>

  <div style="text-align: center; margin: 30px 0;">
    <a href="${APP_URL}" style="background-color: #6366F1; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px; display: inline-block;">Go to OneMind</a>
  </div>

  <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">

  <p style="color: #999; font-size: 12px;">
    Questions about this charge? Reply to this email or contact support.<br>
    <a href="${APP_URL}" style="color: #6366F1;">YOUR_DOMAIN</a>
  </p>
</body>
</html>
    `.trim(),
    text: `
Payment Receipt - OneMind

Hi ${name},

Thank you for your purchase! Here's your receipt:

Date: ${formattedDate}
Item: OneMind Credits
Quantity: ${credits} credits
Total: ${formattedAmount} USD

Transaction ID: ${transactionId}

Your credits have been added to your account and are ready to use.

---
Questions about this charge? Reply to this email or contact support.
onemind.app
    `.trim(),
  };
}

export { APP_URL };
