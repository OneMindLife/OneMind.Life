# OneMind SaaS

Production codebase for [onemind.life](https://onemind.life).

## What's Here

- **Edge Functions** - Production API including Agent API
- **Migrations** - Database schema for production
- **Moltbook Agent** - AI agent for evangelizing on Moltbook

## Open Source

For the open source version, see: https://github.com/onemindlife/onemind.life

## Key Components

| Component | Purpose |
|-----------|---------|
| `supabase/functions/agent-*` | Agent API endpoints |
| `supabase/functions/moltbook-agent` | Moltbook evangelizing agent |
| `supabase/functions/AGENT_API.md` | Agent API documentation |
| `outreach_emails.md` | Outreach tracking |

## Agent API

See `supabase/functions/AGENT_API.md` for documentation.

Base URL: `https://YOUR_PROJECT_REF.supabase.co/functions/v1/`
