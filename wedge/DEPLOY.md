# Deploying the wedge

**Always deploy from the REPO ROOT, never from `wedge/`.**

```bash
cd wedge && npm run build      # rm -rf out && next build  (the rm avoids a stale export)
cd ..                          # ← the important line
firebase deploy --only hosting --project onemind-95fb2
```

`wedge/firebase.json` was DELETED on 2026-08-11. It pointed at the same site
(`onemind-95fb2`) as the root config but carried a DIFFERENT hosting config —
it was missing the root's redirects. Deploying from inside `wedge/` therefore
silently replaced prod's routing: `/upwork` (the Upwork attribution link) began
returning 404, and `/g/GLOBAL` (the Telegram Mini App's entry point) stopped
redirecting to the room. That happened twice in one session before the file was
removed. With only the root config left, the working directory can't change the
outcome.

## Verify after every deploy
Never trust "Deploy complete!" — check the routes and the served bundle:

```bash
for u in /upwork /join/GLOBAL /g/GLOBAL /home /create /c/GLOBAL; do
  printf "%-16s -> %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' https://onemind.life$u)"
done
# expect: 302 302 302 302 302 200
```
# Wedge deploy notes

The wedge is a Next.js **static export** (`out/`) served by Firebase Hosting
on the existing `onemind-95fb2` project.

## ⚠️ Use preview channels — never a plain deploy

`wedge/firebase.json` has `"site": "onemind-95fb2"`, which is the **same site
that serves the live Flutter app** (`onemind.life`). That's required so preview
channel URLs come out as `onemind-95fb2--<channel>-<hash>.web.app`, a pattern
the edge-function CORS allowlist already trusts (see below).

Consequence: **never run `firebase deploy` from here** — it would overwrite the
live Flutter site with the wedge. Only ever deploy a preview channel:

```bash
cd wedge
npm run deploy:preview
```

That runs `next build` then
`firebase hosting:channel:deploy wedge --expires 1d --project onemind-95fb2`.
A preview channel is free, isolated from the live channel (cannot overwrite it),
and auto-expires (here: 1 day — re-running the script resets the clock).

The channel id is fixed (`wedge`), so the URL is **stable across deploys**:
`https://onemind-95fb2--wedge-<hash>.web.app` (the CLI prints it at the end).
Re-deploying replaces that channel's content in place.

## Validate against the deployed channel

```bash
BASE=https://onemind-95fb2--wedge-<hash>.web.app npm run e2e
```

This is the only way to test the production `/c/**` → `/c/_/index.html` rewrite
and the edge-function CORS — `next dev` serves `/c/<code>` natively and so
hides both.

## CORS allowlist — required for ANY permanent home

The `submit-proposition` edge function (the only edge function the wedge calls;
everything else is PostgREST/RPC) enforces an origin allowlist in
`supabase/functions/_shared/cors.ts`. It already allows:
- `localhost` / `127.0.0.1`, `*.trycloudflare.com`, `*.ngrok-free.app`
- Firebase preview channels: `onemind-95fb2--*.web.app`
- `onemind.life` (via the `ALLOWED_ORIGINS` secret)

A **permanent** wedge deploy on any other origin (a named site or a real
domain) must add that origin — either to `ALLOWED_ORIGINS` (Supabase edge
secret) or to `isAllowedOrigin()` — and redeploy `submit-proposition`. Until
then, a named/custom origin will fail at "add idea" with a CORS error while
create/seed (PostgREST) still work.
