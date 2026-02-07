# Flutter Architecture Skill

## Overview

This skill documents the OneMind app architecture patterns for Flutter + Riverpod + Supabase. Use this when:

- Creating new features
- Reviewing PRs
- Debugging state management issues
- Onboarding to the codebase

## Architecture Layers

```
┌─────────────────────────────────────┐
│             UI (Screens)            │
│      ref.watch(xxxProvider)         │
├─────────────────────────────────────┤
│        Providers (providers.dart)   │
│    StateNotifierProvider.family     │
├─────────────────────────────────────┤
│      Notifiers (StateNotifier)      │
│   AsyncValue<State>, Equatable      │
├─────────────────────────────────────┤
│         Services (xxxService)       │
│   Supabase queries, domain models   │
├─────────────────────────────────────┤
│       Models (Equatable, fromJson)  │
│     Domain objects, fail-fast       │
├─────────────────────────────────────┤
│            Supabase                 │
│   PostgreSQL + Realtime + Auth      │
└─────────────────────────────────────┘
```

## Key Files

| Layer | Location | Pattern |
|-------|----------|---------|
| Providers | `lib/providers/providers.dart` | Central barrel file |
| Notifiers | `lib/providers/notifiers/*.dart` | StateNotifier + AsyncValue |
| Services | `lib/services/*.dart` | Supabase injection |
| Models | `lib/models/*.dart` | Equatable + fromJson |
| Errors | `lib/core/errors/app_exception.dart` | Error hierarchy |

## Quick Reference

See:
- `PATTERNS.md` - Detailed pattern descriptions
- `EXAMPLES.md` - Code examples
- `CHECKLIST.md` - PR review checklist
