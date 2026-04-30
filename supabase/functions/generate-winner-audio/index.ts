// Edge Function: generate-winner-audio
// Generates ElevenLabs TTS for official OneMind chat content.
//
// Triggered by DB triggers in two scenarios:
//   1. Round winner finalized → kind: "round", id: round_id
//   2. Official chat created → kind: "chat_initial", id: chat_id
//
// Uploads MP3 to cycle-audio bucket, updates the appropriate audio_url column.
//
// AUTH: verify_jwt = false. Called from pg_net via service role key.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { decodeBase64 } from "jsr:@std/encoding/base64";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const elevenLabsKey = Deno.env.get("ELEVENLABS_API_KEY") ?? "";

const VOICE_ID = "BRS1Pc3W3RYva1gVSaGm";
const MODEL_ID = "eleven_multilingual_v2";
const BUCKET = "cycle-audio";
const LOG_PREFIX = "[GEN-AUDIO]";

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function generateAudio(text: string): Promise<Uint8Array> {
  const url = `https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "xi-api-key": elevenLabsKey,
      "Content-Type": "application/json",
      "Accept": "audio/mpeg",
    },
    body: JSON.stringify({
      text,
      model_id: MODEL_ID,
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.75,
        style: 0.0,
        use_speaker_boost: true,
      },
    }),
  });
  if (!resp.ok) {
    throw new Error(`ElevenLabs ${resp.status}: ${await resp.text()}`);
  }
  return new Uint8Array(await resp.arrayBuffer());
}

async function uploadMp3(path: string, mp3: Uint8Array): Promise<string> {
  const { error } = await supabase.storage.from(BUCKET).upload(path, mp3, {
    contentType: "audio/mpeg",
    upsert: true,
  });
  if (error) throw new Error(`Upload failed: ${error.message}`);
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
  return data.publicUrl;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const body = await req.json();
    const { kind, id } = body as { kind: "round" | "chat_initial"; id: number };

    if (!kind || !id) {
      return new Response(JSON.stringify({ error: "Missing kind or id" }),
        { status: 400, headers: { "Content-Type": "application/json" } });
    }

    if (kind === "round") {
      // Fetch the winning proposition for this round + verify chat is official
      const { data: round, error: roundErr } = await supabase
        .from("rounds")
        .select(`
          id, winning_proposition_id, audio_url,
          cycle:cycles!inner(chat_id, chats!inner(is_official))
        `)
        .eq("id", id)
        .single();

      if (roundErr || !round) {
        console.error(`${LOG_PREFIX} Round not found: ${roundErr?.message}`);
        return new Response(JSON.stringify({ error: "Round not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } });
      }

      // deno-lint-ignore no-explicit-any
      const isOfficial = (round.cycle as any).chats.is_official;
      if (!isOfficial) {
        console.log(`${LOG_PREFIX} Skip: chat not official for round ${id}`);
        return new Response(JSON.stringify({ skipped: true, reason: "not_official" }),
          { status: 200, headers: { "Content-Type": "application/json" } });
      }

      if (round.audio_url) {
        console.log(`${LOG_PREFIX} Skip: audio already exists for round ${id}`);
        return new Response(JSON.stringify({ skipped: true, reason: "exists" }),
          { status: 200, headers: { "Content-Type": "application/json" } });
      }

      if (!round.winning_proposition_id) {
        return new Response(JSON.stringify({ error: "No winning proposition" }),
          { status: 400, headers: { "Content-Type": "application/json" } });
      }

      const { data: prop, error: propErr } = await supabase
        .from("propositions")
        .select("content")
        .eq("id", round.winning_proposition_id)
        .single();

      if (propErr || !prop) {
        return new Response(JSON.stringify({ error: "Proposition not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } });
      }

      console.log(`${LOG_PREFIX} Generating audio for round ${id}: "${prop.content.substring(0, 50)}..."`);
      const mp3 = await generateAudio(prop.content);
      const path = `rounds/round_${id}.mp3`;
      const url = await uploadMp3(path, mp3);

      const { error: updateErr } = await supabase
        .from("rounds")
        .update({ audio_url: url })
        .eq("id", id);

      if (updateErr) {
        console.error(`${LOG_PREFIX} Update failed: ${updateErr.message}`);
        return new Response(JSON.stringify({ error: "Update failed" }),
          { status: 500, headers: { "Content-Type": "application/json" } });
      }

      console.log(`${LOG_PREFIX} Done: round ${id} → ${url}`);
      return new Response(JSON.stringify({ success: true, url }),
        { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (kind === "chat_initial") {
      const { data: chat, error: chatErr } = await supabase
        .from("chats")
        .select("id, is_official, initial_message, initial_message_audio_url")
        .eq("id", id)
        .single();

      if (chatErr || !chat) {
        return new Response(JSON.stringify({ error: "Chat not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } });
      }

      if (!chat.is_official) {
        console.log(`${LOG_PREFIX} Skip: chat ${id} not official`);
        return new Response(JSON.stringify({ skipped: true, reason: "not_official" }),
          { status: 200, headers: { "Content-Type": "application/json" } });
      }

      if (chat.initial_message_audio_url) {
        console.log(`${LOG_PREFIX} Skip: audio already exists for chat ${id}`);
        return new Response(JSON.stringify({ skipped: true, reason: "exists" }),
          { status: 200, headers: { "Content-Type": "application/json" } });
      }

      if (!chat.initial_message) {
        return new Response(JSON.stringify({ error: "No initial message" }),
          { status: 400, headers: { "Content-Type": "application/json" } });
      }

      console.log(`${LOG_PREFIX} Generating audio for chat ${id} initial message`);
      const mp3 = await generateAudio(chat.initial_message);
      const path = `chats/chat_${id}_initial.mp3`;
      const url = await uploadMp3(path, mp3);

      const { error: updateErr } = await supabase
        .from("chats")
        .update({ initial_message_audio_url: url })
        .eq("id", id);

      if (updateErr) {
        console.error(`${LOG_PREFIX} Update failed: ${updateErr.message}`);
        return new Response(JSON.stringify({ error: "Update failed" }),
          { status: 500, headers: { "Content-Type": "application/json" } });
      }

      console.log(`${LOG_PREFIX} Done: chat ${id} initial → ${url}`);
      return new Response(JSON.stringify({ success: true, url }),
        { status: 200, headers: { "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Invalid kind" }),
      { status: 400, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error(`${LOG_PREFIX} Error:`, e);
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: msg }),
      { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
