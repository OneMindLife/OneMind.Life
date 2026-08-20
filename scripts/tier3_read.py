#!/usr/bin/env python3
"""TIER-3 READ — "who's converting deep" in one command.

The acquisition-learning instrument (growth decisions D30/D31). Scores the
funnel at CREATE-AND-PROPOSE, not just "created a chat" — because creation is
hollow on its own (we see ~12 create -> 2 propose). The keyword/source that
produces a *proposer* is the "right person" signal worth doubling down on.

  set -a; source .secrets.env; set +a
  python3 scripts/tier3_read.py [--since YYYY-MM-DD]

Default --since = 2026-06-03 (the day the visitor_source instrument shipped;
events before that carry no visitor_source/keyword — see D30).

WHAT EACH BLOCK ANSWERS (read them together — none is sufficient alone):
  A. PostHog by visitor_source  -> WHICH source reaches depth (attribution).
       CAVEAT: PostHog is blind to ~60-85% of cold ad traffic (adblock/Brave
       eat the beacon, D30). Treat as DIRECTIONAL / a lower bound, not a count.
  B. PostHog top keywords       -> WHICH keyword (utm_term) reaches depth.
       NOTE: empty until the campaign Final URL Suffix carries {keyword}
       ValueTrack. Until then keyword lives only in GA4's native Ads dims.
  C. GA4 + Ads volume           -> full-traffic funnel shape + clicks/cost.
  D. DB ground truth            -> printed SQL to run via Supabase MCP
       (execute_sql, project ccyuxrtrklgpkzcryzpj). The anon key is RLS-blocked
       so this can't be scripted here. DB is the only TRUTH on "did depth happen."
"""
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error

PH_PROJECT = "448142"
PH_HOST = "https://us.posthog.com"
DEFAULT_SINCE = "2026-06-03"

# internal-traffic excludes (PostHog API ignores the project filter — D30)
IP_EXCLUDES = (
    "NOT coalesce(properties.$ip,'') LIKE '2601:983:4600:bcd0%' "
    "AND coalesce(properties.$ip,'') != '73.187.171.6' "
    "AND NOT coalesce(properties.$ip,'') LIKE '2607:fb90:6271:ce7f%'"
)


def posthog(hogql):
    key = os.environ.get("POSTHOG_PERSONAL_API_KEY")
    if not key:
        return None, "POSTHOG_PERSONAL_API_KEY not set"
    body = json.dumps({"query": {"kind": "HogQLQuery", "query": hogql}}).encode()
    req = urllib.request.Request(
        f"{PH_HOST}/api/projects/{PH_PROJECT}/query/",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        data = json.loads(resp.read())
        return (data.get("columns", []), data.get("results", [])), None
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}: {e.read().decode()[:300]}"


def show(title, res, err):
    print(f"\n{title}")
    print("-" * len(title))
    if err:
        print("  (error:", err, ")")
        return
    cols, rows = res
    print("  " + " | ".join(str(c) for c in cols))
    for r in rows:
        print("  " + " | ".join("" if c is None else str(c) for c in r))
    if not rows:
        print("  (no rows yet)")


def main():
    since = DEFAULT_SINCE
    if "--since" in sys.argv:
        since = sys.argv[sys.argv.index("--since") + 1]
    since_ts = f"{since} 00:00:00"
    print(f"=== TIER-3 READ — since {since} (create-AND-propose) ===")

    # A. funnel by visitor_source (attribution; UNDERCOUNTS cold traffic)
    show(
        "A. PostHog funnel by visitor_source  [DIRECTIONAL — undercounts ~60-85% of cold traffic, D30]",
        *posthog(f"""
SELECT
  coalesce(nullIf(properties.visitor_source,''),'(unset)')                       AS source,
  count(DISTINCT if(event='landing_viewed',           properties.$session_id, NULL)) AS landed,
  count(DISTINCT if(event='quick_create_opened',      properties.$session_id, NULL)) AS reached_create,
  count(DISTINCT if(event='quick_create_chat_created',properties.$session_id, NULL)) AS created,
  count(DISTINCT if(event='proposition_submitted',    properties.$session_id, NULL)) AS proposed_TIER3
FROM events
WHERE timestamp >= '{since_ts}' AND {IP_EXCLUDES}
GROUP BY source ORDER BY proposed_TIER3 DESC, created DESC""")
    )

    # A2. fork mix among creators — which path they chose at /create:
    #   group   = "get ideas from the group" (invite others)
    #   options = "provide the options myself"  (+ used_ai=1 if they tapped AI suggest)
    show(
        "A2. Fork mix among creators  [group=invite-others · options=provide-own · used_ai=tapped AI suggest]",
        *posthog(f"""
SELECT coalesce(nullIf(fork,''),'(none)')    AS fork,
       coalesce(nullIf(source,''),'(unset)') AS source,
       used_ai,
       count()                               AS creators
FROM (
  SELECT properties.$session_id AS sid,
         anyIf(properties.fork,           event='quick_create_chat_created') AS fork,
         anyIf(properties.visitor_source, event='quick_create_chat_created') AS source,
         max(event='quick_create_options_ai')                                AS used_ai
  FROM events
  WHERE timestamp >= '{since_ts}' AND {IP_EXCLUDES}
    AND properties.$session_id IN (
      SELECT properties.$session_id FROM events
      WHERE event='quick_create_chat_created' AND timestamp >= '{since_ts}')
  GROUP BY sid)
GROUP BY fork, source, used_ai ORDER BY creators DESC""")
    )

    # B. top keywords among creators (empty until {keyword} ValueTrack suffix is set)
    show(
        "B. PostHog top keywords (utm_term) among creators  [empty until {keyword} ValueTrack suffix is added]",
        *posthog(f"""
SELECT coalesce(nullIf(properties.utm_term,''),'(none)') AS keyword,
       coalesce(nullIf(properties.visitor_source,''),'(unset)') AS source,
       count(DISTINCT properties.$session_id) AS create_sessions
FROM events
WHERE event='quick_create_chat_created' AND timestamp >= '{since_ts}' AND {IP_EXCLUDES}
GROUP BY keyword, source ORDER BY create_sessions DESC LIMIT 25""")
    )

    # C. volume context — Ads clicks + GA4 funnel totals (full traffic)
    print("\nC. VOLUME CONTEXT (full traffic — Ads + GA4)")
    print("-" * 44)
    try:
        ads = subprocess.run(
            [sys.executable, "scripts/ads_query.py", "LAST_7_DAYS"],
            capture_output=True, text=True, timeout=90,
        ).stdout
        for line in ads.splitlines():
            if "ENABLED]" in line and "Website traffic" in line:
                print("  Ads (LAST_7_DAYS):", line.split("::")[1].strip())
    except Exception as e:
        print("  (ads error:", e, ")")
    try:
        ga4 = subprocess.run(
            [sys.executable, "scripts/ga4_query.py", since, "today"],
            capture_output=True, text=True, timeout=90,
        ).stdout
        wanted = ("landing_viewed", "quick_create_opened",
                  "quick_create_chat_created", "proposition_submitted")
        print("  GA4 funnel (full traffic, since", since + "):")
        for line in ga4.splitlines():
            if any(line.strip().startswith(w) for w in wanted):
                print("   ", " ".join(line.split()))
    except Exception as e:
        print("  (ga4 error:", e, ")")

    # D. DB ground truth — run via Supabase MCP (anon key is RLS-blocked here)
    print("\nD. DB GROUND TRUTH — run via Supabase MCP execute_sql (project ccyuxrtrklgpkzcryzpj)")
    print("-" * 44)
    print(f"""  -- real chats created since {since}, and how deep they got (the TRUTH on depth).
  -- author = participant_id; count only NEW props (carried_from_id IS NULL) — carried-
  -- forward winners aren't real participation (CLAUDE.md). chat_id denormalized 2026-06-02.
  SELECT
    count(*) FILTER (WHERE NOT c.is_preview)                       AS real_chats,
    count(*) FILTER (WHERE NOT c.is_preview AND p.n_props > 0)     AS reached_propose_TIER3,
    count(*) FILTER (WHERE NOT c.is_preview AND p.n_parts > 1)     AS multi_participant_TIER4
  FROM chats c
  LEFT JOIN (
    SELECT chat_id,
           count(*) FILTER (WHERE carried_from_id IS NULL)                       AS n_props,
           count(DISTINCT participant_id) FILTER (WHERE carried_from_id IS NULL) AS n_parts
    FROM propositions GROUP BY chat_id
  ) p ON p.chat_id = c.id
  WHERE c.created_at >= '{since}';""")
    print("\nReminder: A/B are directional (PostHog blind spot). D is truth. C is volume. Read together.\n")


if __name__ == "__main__":
    main()
