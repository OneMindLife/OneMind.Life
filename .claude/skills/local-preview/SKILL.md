---
name: local-preview
description: Build, serve, and tunnel the Flutter web app for remote testing, and query prod RemoteLog from `client_logs` to debug issues users hit in production.
---

# Local Preview + Remote Debugging

Two workflows used together to iterate on features:

1. **Preview an unreleased change on a real phone/browser** without deploying — build web, serve locally, expose via tunnel.
2. **See what's happening in prod** when a user hits an error — wire `RemoteLog.log(...)` into the failing path, query `client_logs` via Supabase MCP.

---

## 1. Serve a local build through a public URL

**Default: `flutter build web --debug` + Python static server.** Debug builds run fast (~10–30s per rebuild after the first), and the Python server serves the pre-built files instantly — no compile-on-request latency. A release bundle is the fallback when you specifically need prod artifacts.

> **Why not `flutter run -d web-server`?** It compiles on-demand, which means the first browser reload after any code change sits for 10–30s waiting for `main.dart.js` to be generated. On the tunnel this looks like a stuck loading spinner on the HTML play screen because the Flutter bundle hasn't finished downloading yet. A pre-built bundle avoids that entirely.

### Preferred: debug build + Python server

```bash
flutter build web --debug                    # ~10s incremental, ~60s cold
cd build/web && python3 -m http.server 8080  # serve in background
```

Run the Python server in background (`run_in_background: true`). Iterate:

1. Edit Dart.
2. `flutter build web --debug` — ~10s per rebuild.
3. Reload the browser — instant (the Python server just serves the new files).

Skip/Play buttons on the HTML splash will feel instant because `main.dart.js` is already sitting on disk.

### Fallback: release build (when you need the prod bundle)

```bash
flutter build web --release                  # 1–2 min per change
cd build/web && python3 -m http.server 8080
```

Use this when testing:
- PWA install flow (`beforeinstallprompt`, `display-mode: standalone`)
- Service worker caching behavior (only registered in release mode)
- Minified bundle shape (e.g. `grep`ing `main.dart.js` for specific strings)
- Lighthouse / perf audits against a real release bundle

### Tunnel

**Preferred: Cloudflare** (no bandwidth cap, no auth required for quick tunnels).

```bash
/home/joelc0193/.local/bin/cloudflared tunnel --url http://localhost:8080 --no-autoupdate
```

Grep the output for the generated URL:

```bash
grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' <background-output-file> | head -1
```

**Important CORS note:** the Supabase Edge Functions' CORS allowlist in `supabase/functions/_shared/cors.ts` already allows `*.trycloudflare.com`, `*.ngrok-free.app`, `localhost`, and `127.0.0.1`. If you use a different tunnel host, add it there and redeploy the affected edge functions — otherwise the browser will block the preflight with "Failed to fetch".

**Fallback: ngrok** — has a bandwidth cap on the free tier. Binary at `/home/joelc0193/.npm/_npx/094a17e86d981b10/node_modules/ngrok/bin/ngrok`. URL discovery:

```bash
curl -s http://localhost:4040/api/tunnels | python3 -c "import json,sys; print(json.load(sys.stdin)['tunnels'][0]['public_url'])"
```

### Mobile testing — fresh-user gotcha

When the user loads the tunnel URL on a mobile browser, the origin (`<id>.trycloudflare.com`) is different from `onemind.life`. Their browser has no localStorage for this origin, which means:

- They look like a **brand-new anonymous user** to Supabase.
- The router's `redirect` in `lib/config/router.dart` sees `tutorial_completed = false` and redirects `/` → `/tutorial`. `HomeScreen` never mounts.
- Any logic you added on Home (widgets, `initState` logs, etc.) won't run until the user taps through or skips the tutorial.

**If you're debugging something on Home and seeing zero log output**, the tutorial redirect is the first suspect — not a code bug.

### Iteration with debug build — picking up changes

- Edit any Dart file under `lib/`.
- `flutter build web --debug` — ~10s incremental.
- Reload the browser (plain reload; debug mode registers no service worker, so there's no cache to bust).

If you edit `.arb` files (localization), run `flutter gen-l10n` before `flutter build` — the build doesn't regenerate them automatically.

### Iteration with release build — service worker cache

`flutter build web --release` registers a service worker that aggressively caches the old bundle. To pick up a new release build in the browser:

- **Hard refresh** (Ctrl+Shift+R) — usually one round; occasionally two.
- **DevTools → Application → Service Workers → Unregister**, then reload once. Most reliable.
- Incognito tab — skips the SW entirely; best for showing someone else a fresh build.

### Sanity check — is my code actually in the bundle?

When a change "isn't appearing", verify the server is really serving it before chasing client-side caches:

```bash
# Local file
grep -c "your-new-string-literal" build/web/main.dart.js

# Remote via tunnel — proves the public URL is serving the new bundle
curl -s https://<tunnel>.trycloudflare.com/main.dart.js | grep -c "your-new-string-literal"
```

Non-zero → the bundle is right; problem is client-side (SW cache, wrong URL, etc.). Zero → rebuild didn't include the change.

---

## 2. Remote logging via `client_logs`

### Schema (in prod, not in migrations — created ad-hoc)

```
id           bigint       PK
user_id      uuid         auth.uid() at insert time
event        text         NOT NULL — category/tag, e.g. 'proposition_submit_error'
message      text         free-text summary
metadata     jsonb        arbitrary structured context
created_at   timestamptz  default now()
```

Project ID: `ccyuxrtrklgpkzcryzpj` (OneMind SaaS prod).

### Writing a log from Dart

Service lives at `lib/services/remote_log_service.dart`. Import it:

```dart
import '../../services/remote_log_service.dart';
```

Call:

```dart
RemoteLog.log(
  'proposition_submit_error',     // event — use snake_case tags
  e.toString(),                    // message
  {                                // metadata (optional)
    'error_type': e.runtimeType.toString(),
    'chat_id': chatId,
    'round_id': roundId,
    'content_length': content.length,
    'stack': stack.toString().split('\n').take(12).join('\n'),
  },
);
```

`RemoteLog.log` is silent-fail — it never throws and never blocks. Safe to call from UI paths.

### Where to add logs

- In the `catch` block of the failing operation — include `e.runtimeType`, `e.toString()`, a truncated stack, and the domain IDs that matter for that operation.
- At edge-function / service boundaries — when you have a `FunctionException`, log `e.status`, `e.details`, `e.reasonPhrase` before rethrowing.
- Avoid logging every success — it's write amplification and adds noise. Log errors and unexpected branches only.

### Querying prod

Use the Supabase MCP tool `mcp__supabase__execute_sql` with `project_id: ccyuxrtrklgpkzcryzpj`:

```sql
SELECT id, event, message, metadata, created_at
FROM client_logs
WHERE event = 'proposition_submit_error'
  AND created_at > now() - interval '15 minutes'
ORDER BY created_at DESC
LIMIT 20;
```

Common filters:

- **By user**: `WHERE user_id = '<uuid>'`
- **By time window**: `WHERE created_at > now() - interval '1 hour'`
- **By metadata field**: `WHERE metadata->>'chat_id' = '123'`
- **By error type**: `WHERE metadata->>'error_type' = 'FunctionException'`

### Cleanup when done debugging

When an issue is resolved and you don't want the logging to keep running in prod:

1. Remove the `RemoteLog.log(...)` calls from Dart.
2. Delete any debug rows you don't want kept:
   ```sql
   DELETE FROM client_logs WHERE event = 'proposition_submit_error';
   ```
3. Commit + push.

---

## End-to-end loop

1. One-time setup: `flutter build web --debug` and `cd build/web && python3 -m http.server 8080` (background).
2. One-time setup: Cloudflare tunnel against `:8080`; copy the `*.trycloudflare.com` URL.
3. Reproduce the bug locally, or observe the user report.
4. Add `RemoteLog.log(...)` at the suspected failure point.
5. `flutter build web --debug` — ~10s — then tell the user to reload the tunnel URL.
6. Trigger the bug again (your own browser, or ask the user).
7. Query `client_logs` via MCP to see what actually happened.
8. Ship the fix, then remove or narrow the logging in a follow-up commit.

## Process hygiene

Background processes persist across Claude sessions. Before starting anything new:

```bash
pgrep -af "flutter|python3 -m http.server|cloudflared|ngrok" | head
```

Kill stragglers if the port is held by something stale:

```bash
pkill -f "flutter run -d web-server"
pkill -f "python3 -m http.server 8080"
pkill -f "cloudflared tunnel"
```

Cloudflare's quick tunnels rotate their URL on every restart, so if you kill and relaunch `cloudflared`, grep a fresh URL out of its new output and re-share it.
