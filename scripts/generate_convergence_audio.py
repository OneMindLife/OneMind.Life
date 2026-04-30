#!/usr/bin/env python3
"""
Generate convergence audio (MP3 + word-timing JSON) for a cycle winner using ElevenLabs.

Usage:
  ELEVENLABS_API_KEY=sk_... python3 scripts/generate_convergence_audio.py \\
      --cycle-id 573 \\
      --text "OneMind should become a global hub ..." \\
      --out-dir marketing/convergence_videos/cycle_573

Writes:
  <out-dir>/cycle_<id>.mp3
  <out-dir>/cycle_<id>.json    (word timings — same shape as tutorial audio)

Voice is fixed to the shared OneMind narration voice (BRS1Pc3W3RYva1gVSaGm).
To change the voice, update VOICE_ID below.
"""

import argparse
import base64
import json
import os
import sys
from pathlib import Path
from urllib import request
from urllib.error import HTTPError

VOICE_ID = "BRS1Pc3W3RYva1gVSaGm"
MODEL_ID = "eleven_multilingual_v2"
API_BASE = "https://api.elevenlabs.io"


def generate(text: str, api_key: str) -> tuple[bytes, list[dict]]:
    """Call ElevenLabs /with-timestamps endpoint. Returns (mp3_bytes, word_timings)."""
    url = f"{API_BASE}/v1/text-to-speech/{VOICE_ID}/with-timestamps"
    body = {
        "text": text,
        "model_id": MODEL_ID,
        "voice_settings": {
            "stability": 0.5,
            "similarity_boost": 0.75,
            "style": 0.0,
            "use_speaker_boost": True,
        },
    }
    req = request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={
            "xi-api-key": api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with request.urlopen(req) as resp:
            payload = json.loads(resp.read())
    except HTTPError as e:
        sys.stderr.write(f"ElevenLabs error {e.code}: {e.read().decode()}\n")
        raise

    mp3 = base64.b64decode(payload["audio_base64"])
    alignment = payload.get("alignment") or payload.get("normalized_alignment")
    words = _alignment_to_words(text, alignment)
    return mp3, words


def _alignment_to_words(text: str, alignment: dict) -> list[dict]:
    """Convert ElevenLabs char-level alignment into [{word, start, end}, ...]."""
    if not alignment:
        return []
    chars = alignment["characters"]
    starts = alignment["character_start_times_seconds"]
    ends = alignment["character_end_times_seconds"]

    words = []
    current = []
    word_start = None
    for ch, s, e in zip(chars, starts, ends):
        if ch.isspace():
            if current:
                words.append({
                    "word": "".join(current),
                    "start": round(word_start, 3),
                    "end": round(prev_end, 3),
                })
                current = []
                word_start = None
        else:
            if not current:
                word_start = s
            current.append(ch)
            prev_end = e
    if current:
        words.append({
            "word": "".join(current),
            "start": round(word_start, 3),
            "end": round(prev_end, 3),
        })
    return words


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cycle-id", type=int, required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        sys.exit("ELEVENLABS_API_KEY env var is required")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    mp3, words = generate(args.text, api_key)

    mp3_path = out_dir / f"cycle_{args.cycle_id}.mp3"
    json_path = out_dir / f"cycle_{args.cycle_id}.json"
    mp3_path.write_bytes(mp3)
    json_path.write_text(json.dumps(words))

    print(f"Wrote {mp3_path} ({len(mp3)} bytes, {len(words)} words)")
    print(f"Wrote {json_path}")


if __name__ == "__main__":
    main()
