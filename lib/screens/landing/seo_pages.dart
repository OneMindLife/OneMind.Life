import 'package:flutter/material.dart';

import 'seo_landing_page.dart';

/// All SEO keyword landing pages.
///
/// Each targets a different keyword cluster to maximize organic search coverage.
/// Add new pages here and register their routes in router.dart + route_metadata.dart.
const seoPages = <String, SeoPageData>{
  // ── 1. Decision Making Tool ──
  'decision-making-tool': SeoPageData(
    slug: 'decision-making-tool',
    heroHeadline: 'The Group Decision\nMaking Tool That Works',
    heroSubheadline:
        'Stop letting the loudest voice win. OneMind gives every team member '
        'an equal say through anonymous proposals and transparent rating — '
        'so your group decisions are actually trusted.',
    ctaLabel: 'Make Better Decisions',
    problemHeadline: 'Group decisions shouldn\u2019t be this hard',
    problemDescription:
        'Meetings drag on. Opinions get steamrolled. Decisions get made by '
        'whoever talks the most, not whoever has the best idea. Your team '
        'deserves a decision-making process that\u2019s fair, fast, and '
        'transparent.',
    steps: [
      SeoStep(
        icon: Icons.edit_note,
        title: 'Submit Ideas',
        description:
            'Everyone on your team proposes solutions anonymously. '
            'No names attached means no bias — ideas stand on their own.',
      ),
      SeoStep(
        icon: Icons.how_to_vote,
        title: 'Rate Fairly',
        description:
            'Each person rates every proposal on a simple scale. '
            'The group\u2019s collective judgment surfaces the best ideas.',
      ),
      SeoStep(
        icon: Icons.emoji_events_outlined,
        title: 'Decide Together',
        description:
            'When the same idea wins across multiple rounds, that\u2019s '
            'real consensus. A decision everyone can stand behind.',
      ),
    ],
    features: [
      SeoFeature(
        icon: Icons.visibility_off,
        title: 'Anonymous Proposals',
        description:
            'Remove politics from decision making. When ideas are anonymous, '
            'they\u2019re judged on merit — not on who said them.',
      ),
      SeoFeature(
        icon: Icons.devices,
        title: 'Works Asynchronously',
        description:
            'No need to schedule a meeting. Team members contribute and rate '
            'on their own time. Decisions happen without calendar conflicts.',
      ),
      SeoFeature(
        icon: Icons.trending_up,
        title: 'Auditable Results',
        description:
            'Every rating is recorded. Every outcome is transparent. '
            'Your team can see exactly how a decision was reached.',
      ),
    ],
    proofLine:
        'Used by teams, communities, and organizations making decisions '
        'they can trust.',
    closingHeadline: 'Ready to make decisions your team trusts?',
    closingSubheadline:
        'Try OneMind free — no account needed, start in 30 seconds.',
  ),

  // ── 2. Consensus Building ──
  'consensus-building': SeoPageData(
    slug: 'consensus-building',
    heroHeadline: 'Build Real Consensus,\nNot Forced Agreement',
    heroSubheadline:
        'OneMind\u2019s structured rounds help groups converge on the '
        'strongest idea naturally. No compromise, no coercion — just '
        'genuine group alignment.',
    ctaLabel: 'Build Consensus Now',
    problemHeadline: 'Consensus doesn\u2019t mean everyone agrees to disagree',
    problemDescription:
        'Traditional consensus-building is slow, frustrating, and often '
        'ends in watered-down compromises nobody loves. Real consensus '
        'means finding the answer the group genuinely believes in — and '
        'that requires a better process.',
    steps: [
      SeoStep(
        icon: Icons.lightbulb_outline,
        title: 'Propose',
        description:
            'Every participant submits their best idea anonymously. '
            'Multiple perspectives surface without groupthink.',
      ),
      SeoStep(
        icon: Icons.star_outline,
        title: 'Rate',
        description:
            'The group rates all proposals fairly. No lobbying, no '
            'side conversations — just honest individual assessment.',
      ),
      SeoStep(
        icon: Icons.loop,
        title: 'Converge',
        description:
            'Ideas compete across rounds. When one wins repeatedly, '
            'that\u2019s convergence — the group\u2019s authentic consensus.',
      ),
    ],
    features: [
      SeoFeature(
        icon: Icons.balance,
        title: 'Fair by Design',
        description:
            'Every voice carries equal weight. Anonymous proposing and '
            'individual rating eliminate social pressure and hierarchy.',
      ),
      SeoFeature(
        icon: Icons.auto_awesome,
        title: 'Convergence, Not Compromise',
        description:
            'Unlike voting, OneMind\u2019s multi-round process finds '
            'the idea the group truly believes in — not just the least '
            'objectionable option.',
      ),
      SeoFeature(
        icon: Icons.groups,
        title: 'Any Group Size',
        description:
            'From 3-person teams to 100-person communities. The process '
            'scales without losing fairness or transparency.',
      ),
    ],
    proofLine:
        'Groups reach genuine consensus in minutes instead of hours.',
    closingHeadline: 'Stop compromising. Start converging.',
    closingSubheadline:
        'Experience real consensus building — free, no sign-up required.',
  ),

  // ── 3. Facilitation Tool ──
  'facilitation-tool': SeoPageData(
    slug: 'facilitation-tool',
    heroHeadline: 'The Facilitation Tool\nThat Runs Itself',
    heroSubheadline:
        'OneMind automates the hardest parts of facilitation — equal '
        'participation, fair evaluation, and transparent outcomes. '
        'Your process stays structured whether you\u2019re there or not.',
    ctaLabel: 'Try It Free',
    problemHeadline: 'Facilitation shouldn\u2019t depend on one person',
    problemDescription:
        'Great facilitators are rare and expensive. Without one, group '
        'processes fall apart — dominant voices take over, quiet people '
        'disengage, and outcomes feel unfair. You need a process that '
        'guarantees fairness by design.',
    steps: [
      SeoStep(
        icon: Icons.people_outline,
        title: 'Gather Your Group',
        description:
            'Create a session and share the invite link. Participants '
            'join from any device — no app download needed.',
      ),
      SeoStep(
        icon: Icons.auto_fix_high,
        title: 'The Process Runs',
        description:
            'OneMind handles the structure: timed rounds, anonymous '
            'proposals, fair rating. Everyone participates equally.',
      ),
      SeoStep(
        icon: Icons.check_circle_outline,
        title: 'Results Emerge',
        description:
            'The strongest ideas surface through multiple rounds. '
            'Transparent, auditable, and trusted by the whole group.',
      ),
    ],
    features: [
      SeoFeature(
        icon: Icons.timer,
        title: 'Timed Rounds',
        description:
            'Built-in timers keep things moving. No more sessions that '
            'drag on without resolution.',
      ),
      SeoFeature(
        icon: Icons.lock_outline,
        title: 'Structured Fairness',
        description:
            'Anonymous proposals prevent anchoring bias. Equal rating '
            'prevents dominance. The process enforces what facilitators '
            'strive for.',
      ),
      SeoFeature(
        icon: Icons.wifi_off,
        title: 'Asynchronous Option',
        description:
            'Run facilitated processes without scheduling a meeting. '
            'Participants contribute when it suits them.',
      ),
    ],
    proofLine:
        'Designed for facilitators, consultants, coaches, and '
        'team leaders who want fair outcomes every time.',
    closingHeadline: 'Facilitation that scales.',
    closingSubheadline:
        'Let OneMind handle the process while you focus on the people.',
  ),

  // ── 4. Loomio Alternative ──
  'loomio-alternative': SeoPageData(
    slug: 'loomio-alternative',
    heroHeadline: 'Looking for a\nLoomio Alternative?',
    heroSubheadline:
        'OneMind takes a fundamentally different approach to group decisions. '
        'Instead of threaded discussions that go in circles, our structured '
        'rounds drive real convergence — fast.',
    ctaLabel: 'Try OneMind Free',
    problemHeadline: 'Discussion threads don\u2019t build consensus',
    problemDescription:
        'Tools like Loomio rely on open discussion before a vote. But '
        'discussions get dominated by the most vocal. Votes split the '
        'group. And "consensus" ends up meaning "nobody objected loudly '
        'enough." There\u2019s a better way.',
    steps: [
      SeoStep(
        icon: Icons.edit_note,
        title: 'Anonymous Proposals',
        description:
            'Unlike Loomio\u2019s open discussions, OneMind starts '
            'with anonymous idea submission. No anchoring, no groupthink.',
      ),
      SeoStep(
        icon: Icons.star_outline,
        title: 'Fair Rating',
        description:
            'Instead of up/down votes, everyone rates every idea. '
            'Nuanced evaluation replaces binary choices.',
      ),
      SeoStep(
        icon: Icons.emoji_events_outlined,
        title: 'True Convergence',
        description:
            'Ideas compete across rounds until one wins consistently. '
            'That\u2019s genuine consensus — not just a majority vote.',
      ),
    ],
    features: [
      SeoFeature(
        icon: Icons.visibility_off,
        title: 'Anonymous vs. Open',
        description:
            'Loomio\u2019s open discussions favor confident speakers. '
            'OneMind\u2019s anonymous proposals level the playing field.',
      ),
      SeoFeature(
        icon: Icons.loop,
        title: 'Rounds vs. Threads',
        description:
            'Instead of endless threaded discussions, OneMind uses '
            'structured rounds that naturally drive toward convergence.',
      ),
      SeoFeature(
        icon: Icons.speed,
        title: 'Minutes vs. Days',
        description:
            'Loomio discussions can drag for days. OneMind\u2019s timed '
            'rounds reach consensus in minutes — asynchronously if needed.',
      ),
    ],
    proofLine:
        'For teams who want real consensus, not discussion fatigue.',
    closingHeadline: 'Ready to try a different approach?',
    closingSubheadline:
        'See how OneMind\u2019s structured rounds compare to '
        'Loomio\u2019s discussion threads.',
  ),
};
