/// A blog post's metadata and content.
class BlogPost {
  final String slug;
  final String title;
  final String metaDescription;
  final String date; // YYYY-MM-DD
  final String author;
  final List<String> keywords;
  final List<BlogSection> sections;

  const BlogPost({
    required this.slug,
    required this.title,
    required this.metaDescription,
    required this.date,
    required this.author,
    required this.keywords,
    required this.sections,
  });
}

/// A content section within a blog post.
sealed class BlogSection {
  const BlogSection();
}

class BlogParagraph extends BlogSection {
  final String text;
  const BlogParagraph(this.text);
}

class BlogHeading extends BlogSection {
  final String text;
  const BlogHeading(this.text);
}

class BlogSubheading extends BlogSection {
  final String text;
  const BlogSubheading(this.text);
}

class BlogBulletList extends BlogSection {
  final List<String> items;
  const BlogBulletList(this.items);
}

class BlogCta extends BlogSection {
  final String text;
  final String buttonLabel;
  final String route;
  const BlogCta({
    required this.text,
    required this.buttonLabel,
    required this.route,
  });
}

class BlogDivider extends BlogSection {
  const BlogDivider();
}

class BlogDiagram extends BlogSection {
  const BlogDiagram();
}

/// All published blog posts, newest first.
final blogPosts = <BlogPost>[
  _asyncDecisionMaking,
  _anonymousDecisionMaking,
  _votingVsConsensus,
  _groupDecisionMakingMethods,
];

// ---------------------------------------------------------------------------
// Post 4: Async Decision Making for Remote Teams
// ---------------------------------------------------------------------------

const _asyncDecisionMaking = BlogPost(
  slug: 'async-decision-making-remote-teams',
  title: 'Async Decision Making for Remote Teams: '
      'How to Align Without Meetings',
  metaDescription:
      'Remote teams waste hours in sync meetings that could be async. '
      'Learn why asynchronous decision making produces better alignment '
      'and how structured convergence makes it practical.',
  date: '2026-03-27',
  author: 'Joel Castro',
  keywords: [
    'async decision making tools for remote teams',
    'asynchronous decision making',
    'remote team decisions',
    'async collaboration tools',
    'distributed team alignment',
  ],
  sections: [
    BlogHeading('The Meeting That Could Have Been an Email '
        '\u2014 And the Email That Solved Nothing'),
    BlogParagraph(
      'It\u2019s 8 AM in New York. Your engineering lead in Berlin has '
      'been online for six hours. Your designer in Tokyo already signed '
      'off. And someone just scheduled a \u201cquick alignment call\u201d '
      'for 4 PM UTC \u2014 which is dinner time in Berlin, midnight in '
      'Tokyo, and right in the middle of deep work for New York.',
    ),
    BlogParagraph(
      'The call happens anyway. Half the team attends live. The rest '
      'watch a recording three days later and reply with comments that '
      'nobody reads because the decision already got made by whoever '
      'showed up.',
    ),
    BlogParagraph(
      'This is the default decision-making process for most distributed '
      'teams. And it\u2019s broken in ways that \u201cbetter meeting '
      'hygiene\u201d can\u2019t fix.',
    ),
    BlogParagraph(
      'The problem isn\u2019t that your team needs better meetings. '
      'It\u2019s that synchronous decision making fundamentally doesn\u2019t '
      'work when your team spans time zones, schedules, and working '
      'styles. What you need are async decision making tools for remote '
      'teams \u2014 approaches that let people contribute their best '
      'thinking on their own time, then converge on an answer everyone '
      'can support.',
    ),
    BlogDivider(),

    BlogHeading('Why Synchronous Decisions Fail Remote Teams'),
    BlogSubheading('Time zone math is a tax on participation'),
    BlogParagraph(
      'For a team spanning three or more time zones, there is no '
      '\u201cgood\u201d meeting time. Someone is always attending at '
      'an inconvenient hour. Over time, the people in the \u201cwrong\u201d '
      'time zone participate less, contribute less, and quietly '
      'disengage from decisions that affect their work.',
    ),
    BlogSubheading('Meetings reward presence, not quality'),
    BlogParagraph(
      'In a live meeting, the people who happen to be alert, prepared, '
      'and comfortable speaking up have outsized influence. The loudest '
      'voice in the room often wins \u2014 not because their idea is '
      'best, but because the process rewards confidence over substance. '
      'This problem compounds remotely, where connection issues and '
      'camera fatigue further skew who gets heard.',
    ),
    BlogSubheading('Recordings don\u2019t equal participation'),
    BlogParagraph(
      'Teams try to solve the timezone problem by recording meetings. '
      'But watching a 45-minute recording is passive consumption, not '
      'participation. By the time someone comments, the group has '
      'moved on.',
    ),
    BlogSubheading('Decision fatigue multiplied'),
    BlogParagraph(
      'Remote workers attend more meetings than their in-office '
      'counterparts. Each meeting demands a context switch, draining '
      'the cognitive energy that would have produced better thinking '
      'in an asynchronous format.',
    ),
    BlogDivider(),

    BlogHeading('Async Approaches: The Promise and the Limits'),
    BlogSubheading('Slack polls and emoji votes'),
    BlogParagraph(
      'The most common async \u201cdecision tool\u201d for remote teams '
      'is a Slack poll or emoji reaction. Someone posts a question, '
      'people react, the most popular emoji wins.',
    ),
    BlogBulletList([
      'Pros: Zero friction, everyone knows how to use it, instant results.',
      'Cons: Whoever writes the poll controls the options. No nuance. '
          'Early votes anchor later ones. No mechanism for ideas to evolve.',
    ]),
    BlogSubheading('Email and document threads'),
    BlogParagraph(
      'Someone writes a proposal in a Google Doc or email, and the team '
      'comments. This gives everyone time to think and respond.',
    ),
    BlogBulletList([
      'Pros: Asynchronous by nature, supports long-form thinking, '
          'creates a paper trail.',
      'Cons: Threads fracture. Loud voices still dominate via word '
          'count. No clear mechanism to resolve disagreement. Decisions '
          'stall in \u201cstill discussing\u201d limbo.',
    ]),
    BlogSubheading('Dedicated async tools (Loomio, Range)'),
    BlogParagraph(
      'Purpose-built tools offer structured proposals with voting, '
      'threads, and deadlines. A step up from Slack polls, but most '
      'still rely on voting mechanics with their well-documented '
      'limitations. Proposals are tied to names, introducing bias. '
      'One-round voting means the group commits before ideas have '
      'been stress-tested.',
    ),
    BlogDivider(),

    BlogHeading('What Effective Async Decision Making Actually Needs'),
    BlogBulletList([
      'Equal access: Everyone participates on their own schedule, '
          'regardless of time zone.',
      'Anonymous input: Ideas compete on merit, not on who proposed them.',
      'Structured evaluation: Not thumbs-up/thumbs-down, but nuanced '
          'rating across all proposals.',
      'Iteration: Ideas get tested over multiple rounds, not locked in '
          'after a single vote.',
      'Clear resolution: A defined endpoint so decisions don\u2019t '
          'languish in \u201copen\u201d status indefinitely.',
    ]),
    BlogDivider(),

    BlogHeading('Structured Convergence: The Missing Async Decision '
        'Making Tool for Remote Teams'),
    BlogParagraph(
      'Structured convergence \u2014 anonymous proposing, rating, and '
      'iterative rounds \u2014 turns out to be naturally asynchronous. '
      'It works better async than sync, because it was designed around '
      'written contributions rather than verbal debate.',
    ),
    BlogSubheading('Step 1: Everyone proposes on their own time'),
    BlogParagraph(
      'A question goes out to the group. Each person submits their '
      'proposed answer anonymously within a time window \u2014 hours or '
      'days, not minutes. Your Tokyo team member contributes during '
      'their morning. Your Berlin lead adds theirs after lunch. Nobody '
      'missed the meeting because there was no meeting.',
    ),
    BlogSubheading('Step 2: Everyone rates every idea'),
    BlogParagraph(
      'Once proposals are in, each participant evaluates every idea. '
      'Not a binary vote, but a comparative rating that captures '
      'nuance. Because ideas are anonymous, the evaluation is based '
      'purely on substance.',
    ),
    BlogSubheading('Step 3: Top ideas advance, new ideas enter'),
    BlogParagraph(
      'The highest-rated proposals carry forward to the next round. '
      'Participants can submit new ideas to compete alongside the '
      'winners. Ideas get pressure-tested across rounds.',
    ),
    BlogSubheading('Step 4: Convergence resolves the decision'),
    BlogParagraph(
      'When the same idea wins back-to-back rounds, that\u2019s '
      'convergence \u2014 genuine group alignment. The entire process '
      'happens asynchronously. No scheduling conflicts. No time zone '
      'math.',
    ),
    BlogDiagram(),
    BlogDivider(),

    BlogHeading('Real-World Examples: Async Decisions in Practice'),
    BlogSubheading('Distributed engineering team: Quarterly priorities'),
    BlogParagraph(
      'A 15-person engineering team across San Francisco, London, and '
      'Singapore needs to decide which technical debt to tackle in Q3. '
      'With async structured convergence, all 15 engineers submit '
      'proposals during their regular hours. Anonymous rating ensures '
      'the Singapore team\u2019s input carries equal weight. After two '
      'rounds over three days, the team converges on a database '
      'migration that the architects hadn\u2019t prioritized but the '
      'team collectively identified as the biggest bottleneck.',
    ),
    BlogSubheading('Cross-timezone committee: Nonprofit policy update'),
    BlogParagraph(
      'A global nonprofit\u2019s advisory committee spans six time '
      'zones. Instead of three weeks of calendar coordination, they '
      'post the policy question with a 48-hour proposing window and '
      '24-hour rating window per round. Three rounds produce '
      'convergence incorporating perspectives from every region. '
      'Total time per participant: under 30 minutes.',
    ),
    BlogSubheading('Hybrid organization: Product roadmap'),
    BlogParagraph(
      'A 40-person company with half the team remote faces a persistent '
      'problem: in-office employees dominate roadmap decisions via '
      'hallway conversations. Async convergence levels the field. '
      'Every team member submits feature proposals anonymously. The '
      'roadmap reflects the genuine priorities of the entire team, '
      'not just those with physical proximity to decision-makers.',
    ),
    BlogDivider(),

    BlogHeading('When Async Isn\u2019t the Right Call'),
    BlogBulletList([
      'Crisis response: If the server is down, you need a war room, '
          'not an async poll.',
      'Relationship building: Some meetings exist for trust and '
          'rapport, not decisions.',
      'Creative brainstorming: Live riffing has genuine value for '
          'early-stage ideation.',
      'Very small, high-trust teams: A three-person founding team '
          'probably doesn\u2019t need formal async structure.',
    ]),
    BlogDivider(),

    BlogHeading('Making the Shift: Practical Tips'),
    BlogSubheading('Audit your meetings first'),
    BlogParagraph(
      'Which recurring meetings exist primarily to make decisions? '
      'For each one, ask: \u201cCould this decision be made better if '
      'everyone had time to think before responding?\u201d If yes, '
      'that meeting is a candidate for async conversion.',
    ),
    BlogSubheading('Set explicit time windows'),
    BlogParagraph(
      'Instead of \u201crespond by Friday,\u201d try \u201cproposing '
      'window: Tuesday 9 AM to Thursday 9 AM UTC.\u201d Time windows '
      'give every time zone a full working day to participate.',
    ),
    BlogSubheading('Separate proposing from evaluating'),
    BlogParagraph(
      'Let everyone submit ideas first. Then evaluate as a separate '
      'step. This prevents anchoring \u2014 the first idea posted in '
      'a Slack thread no longer sets the frame for everything after.',
    ),
    BlogSubheading('Make anonymity the default'),
    BlogParagraph(
      'Remote teams have invisible power dynamics: the person in the '
      'CEO\u2019s time zone, the one who responds fastest in Slack. '
      'Anonymous proposing and rating neutralize all of these.',
    ),
    BlogDivider(),

    BlogHeading('Try Async Convergence with OneMind'),
    BlogParagraph(
      'OneMind is a free consensus-building app built for exactly this '
      'problem. Groups propose ideas anonymously, rate them fairly, and '
      'repeat rounds until one idea wins back-to-back \u2014 all '
      'asynchronously. No scheduling. No time zone math. No meetings.',
    ),
    BlogCta(
      text: 'If your team is tired of meetings that don\u2019t decide '
          'anything and Slack polls that oversimplify everything, '
          'OneMind is the async decision making tool built for how '
          'remote teams actually work.',
      buttonLabel: 'Try OneMind Free',
      route: '/tutorial',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Post 3: Anonymous Decision Making
// ---------------------------------------------------------------------------

const _anonymousDecisionMaking = BlogPost(
  slug: 'anonymous-decision-making',
  title: 'Anonymous Decision Making: Why Removing Names '
      'Leads to Better Group Decisions',
  metaDescription:
      'When ideas are tied to names, bias wins. Learn why anonymous '
      'decision making produces better outcomes and how structured '
      'convergence makes it practical for any team.',
  date: '2026-03-27',
  author: 'Joel Castro',
  keywords: [
    'anonymous decision making tool for teams',
    'anonymous group decisions',
    'anonymous voting tool',
    'bias-free decision making',
  ],
  sections: [
    // Intro
    BlogHeading('The Hidden Cost of Knowing Who Said What'),
    BlogParagraph(
      'Picture a typical team meeting. The VP shares an idea. A few '
      'people nod. A junior developer has a better approach but stays '
      'quiet because contradicting the VP feels risky. Someone else '
      'builds on the VP\u2019s idea \u2014 not because it\u2019s the '
      'strongest, but because agreeing with leadership is the path of '
      'least resistance.',
    ),
    BlogParagraph(
      'The meeting ends. A decision gets made. And the best idea in '
      'the room never got heard.',
    ),
    BlogParagraph(
      'This isn\u2019t a failure of talent or intention. It\u2019s a '
      'structural problem: when people know who proposed an idea, they '
      'can\u2019t help but evaluate the person alongside the idea. '
      'Decades of organizational research confirm what most of us '
      'already feel \u2014 hierarchy, confidence, and social dynamics '
      'shape group outcomes more than the actual quality of the '
      'proposals on the table.',
    ),
    BlogParagraph(
      'Anonymous decision making fixes this by design. And in this '
      'article, we\u2019ll explore exactly why removing names from the '
      'process leads to better group decisions \u2014 along with '
      'practical approaches you can use starting today.',
    ),
    BlogDivider(),

    // Why Names Poison Group Decisions
    BlogHeading('Why Names Poison Group Decisions'),
    BlogParagraph(
      'Before we talk solutions, it\u2019s worth understanding the '
      'specific biases that creep in when ideas are attached to '
      'identities. These aren\u2019t character flaws \u2014 they\u2019re '
      'well-documented cognitive patterns that affect everyone.',
    ),
    BlogSubheading('Authority bias'),
    BlogParagraph(
      'When a manager or senior team member proposes something, the '
      'group tends to defer. Not because the idea is best, but because '
      'disagreeing with authority carries social cost. Studies show that '
      'teams are significantly more likely to adopt a proposal from a '
      'high-status member \u2014 regardless of objective quality.',
    ),
    BlogSubheading('Anchoring'),
    BlogParagraph(
      'The first idea shared in a discussion sets an anchor. Subsequent '
      'proposals get evaluated relative to it, not on their own merits. '
      'If the CEO speaks first (and they usually do), every other idea '
      'is unconsciously measured against that anchor.',
    ),
    BlogSubheading('Conformity pressure'),
    BlogParagraph(
      'Solomon Asch\u2019s conformity experiments showed that people '
      'will give obviously wrong answers just to match the group. In '
      'professional settings, this manifests as quiet agreement \u2014 '
      'nodding along in meetings, not raising objections, \u201cgoing '
      'with the flow.\u201d The result is decisions that seem like '
      'consensus but are actually just compliance.',
    ),
    BlogSubheading('The loudness problem'),
    BlogParagraph(
      'Research consistently shows that the person who talks the most '
      'in a meeting has disproportionate influence on the outcome \u2014 '
      'even when their contributions aren\u2019t the highest quality. '
      'Extroverts and confident speakers dominate group discussions not '
      'because they have better ideas, but because the process rewards '
      'volume over substance.',
    ),
    BlogParagraph(
      'These biases don\u2019t disappear with good intentions. The only '
      'reliable solution is structural: remove the information that '
      'triggers the bias in the first place.',
    ),
    BlogDivider(),

    // How Anonymous Decision Making Changes the Equation
    BlogHeading('How Anonymous Decision Making Changes the Equation'),
    BlogParagraph(
      'An anonymous decision making tool for teams doesn\u2019t just '
      'hide names \u2014 it fundamentally restructures how ideas compete.',
    ),
    BlogSubheading('Ideas stand on their own merit'),
    BlogParagraph(
      'When nobody knows who proposed \u201crestructure the Q3 '
      'timeline\u201d versus \u201cadd a two-week buffer,\u201d each '
      'idea gets evaluated purely on its substance. The intern\u2019s '
      'idea competes on equal footing with the director\u2019s.',
    ),
    BlogSubheading('Quiet voices get heard'),
    BlogParagraph(
      'In a typical meeting, introverts, new team members, and people '
      'from underrepresented groups are statistically less likely to '
      'speak up. Anonymous group decisions eliminate the social risk of '
      'proposing something. You don\u2019t need confidence to share an '
      'idea \u2014 you just need the idea itself.',
    ),
    BlogSubheading('Honesty increases'),
    BlogParagraph(
      'When there\u2019s no social penalty for disagreeing with the '
      'popular option, people rate proposals based on what they actually '
      'think \u2014 not what they think they should say.',
    ),
    BlogSubheading('Better ideas surface'),
    BlogParagraph(
      'When you remove bias from evaluation and lower the barrier to '
      'participation, the pool of ideas gets larger and the selection '
      'process gets fairer. Organizations that use anonymous ideation '
      'processes report higher team satisfaction with outcomes and '
      'stronger follow-through on decisions.',
    ),
    BlogDivider(),

    // Common Approaches
    BlogHeading('Common Approaches to Anonymous Group Decisions'),
    BlogParagraph(
      'Anonymous decision making isn\u2019t new. Several established '
      'methods use anonymity in different ways. If you\u2019re exploring '
      'group decision-making methods, here\u2019s how the anonymous '
      'options compare:',
    ),
    BlogSubheading('Anonymous surveys'),
    BlogParagraph(
      'The simplest approach. Send out a form and collect responses '
      'without names. Easy to set up and familiar to everyone. But '
      'it\u2019s one-shot \u2014 you collect opinions but there\u2019s '
      'no mechanism for ideas to evolve or compete.',
    ),
    BlogSubheading('The Delphi Method'),
    BlogParagraph(
      'Developed by the RAND Corporation in the 1950s, the Delphi '
      'Method collects anonymous expert opinions across multiple rounds. '
      'It\u2019s well-researched but designed for expert panels, not '
      'everyday teams. Takes days or weeks per cycle and requires a '
      'dedicated facilitator.',
    ),
    BlogSubheading('Anonymous voting tools'),
    BlogParagraph(
      'Tools like Slido or Mentimeter let groups vote anonymously in '
      'real time. Fast and engaging \u2014 but they anonymize the '
      'voting, not the proposing. Someone still has to stand up and '
      'suggest the options. As we explored in Voting vs. Consensus, '
      'whoever frames the options controls the outcome.',
    ),
    BlogSubheading('Suggestion boxes'),
    BlogParagraph(
      'The classic anonymous input method. Zero barrier to '
      'participation and truly anonymous \u2014 but no evaluation '
      'mechanism. Ideas go in but there\u2019s no structured way for '
      'the group to rate, compare, or iterate on them.',
    ),
    BlogDivider(),

    // What's Missing
    BlogHeading('What\u2019s Missing from These Approaches'),
    BlogParagraph(
      'Notice a pattern? Most anonymous decision-making tools solve '
      'part of the problem but leave gaps:',
    ),
    BlogBulletList([
      'Anonymous surveys anonymize input but don\u2019t help the group '
          'evaluate or converge.',
      'The Delphi Method adds rounds but requires heavy facilitation '
          'and isn\u2019t practical for routine decisions.',
      'Anonymous voting tools anonymize evaluation but not proposal '
          'generation \u2014 so bias enters at the framing stage.',
      'Suggestion boxes anonymize proposals but have no evaluation '
          'process at all.',
    ]),
    BlogParagraph(
      'The ideal anonymous decision making tool for teams would combine '
      'all three elements: anonymous proposing, anonymous rating, and '
      'multiple rounds so the group genuinely converges.',
    ),
    BlogDivider(),

    // Structured Convergence
    BlogHeading('Structured Convergence: Anonymity That Actually Works'),
    BlogParagraph(
      'This is the approach behind structured convergence \u2014 and '
      'it\u2019s what OneMind was built to automate.',
    ),
    BlogSubheading('Step 1: Everyone proposes anonymously'),
    BlogParagraph(
      'The group receives a question or decision prompt. Every '
      'participant submits their proposed answer \u2014 with no names '
      'attached. There\u2019s a time limit to keep things moving. '
      'A team of 8 might generate 8 different proposals in the time '
      'it would take to discuss 2 in a traditional meeting.',
    ),
    BlogSubheading('Step 2: Everyone rates every idea'),
    BlogParagraph(
      'Instead of a binary vote, each participant evaluates every '
      'proposal. This captures nuance that up-or-down voting misses. '
      'An idea that\u2019s everyone\u2019s strong second choice often '
      'turns out to be the strongest consensus option.',
    ),
    BlogSubheading('Step 3: Top ideas carry forward'),
    BlogParagraph(
      'The highest-rated proposals advance to the next round. '
      'Participants can submit new ideas to compete alongside the '
      'carried-forward winners. Ideas have to prove themselves across '
      'multiple rounds.',
    ),
    BlogSubheading('Step 4: Convergence'),
    BlogParagraph(
      'When the same idea wins back-to-back rounds, that\u2019s '
      'convergence \u2014 genuine group alignment, not a forced '
      'compromise. The process terminates naturally when the group '
      'has found its answer.',
    ),
    BlogDiagram(),
    BlogDivider(),

    // Real-World Examples
    BlogHeading('Real-World Examples'),
    BlogSubheading('Workplace: Choosing a new project management tool'),
    BlogParagraph(
      'A 20-person engineering team needs to standardize on a project '
      'management tool. With anonymous proposing, all 20 engineers '
      'submit their recommendation without names. After two rounds, '
      'the team converges on a tool that 17 out of 20 rated highly '
      '\u2014 one the team lead hadn\u2019t even considered. Adoption '
      'is smooth because the process felt fair.',
    ),
    BlogSubheading('Committee: Allocating a community grant budget'),
    BlogParagraph(
      'A nonprofit committee with board members, community reps, and '
      'staff needs to allocate \$50,000 across competing programs. '
      'Anonymous proposals level the field. Rating reveals the group '
      'agrees on 80% of the allocation \u2014 focusing discussion on '
      'the remaining 20%. Total time: 45 minutes instead of three '
      'contentious meetings.',
    ),
    BlogSubheading('Student organization: Planning the annual event'),
    BlogParagraph(
      'A university student government plans its flagship event. '
      'Anonymous submission generates proposals from every member '
      '\u2014 including creative formats newer members would never '
      'have pitched in an open meeting. A hybrid concept emerges as '
      'the convergence winner after three rounds.',
    ),
    BlogDivider(),

    // When Anonymity Isn't Right
    BlogHeading('When Anonymity Isn\u2019t the Right Call'),
    BlogParagraph(
      'Intellectual honesty requires acknowledging that anonymous '
      'decision making isn\u2019t universally superior:',
    ),
    BlogBulletList([
      'Accountability matters more than ideation \u2014 if you need to '
          'know who committed to what, anonymity defeats the purpose.',
      'The group is very small and trusts each other deeply.',
      'Expertise needs to be weighted \u2014 in some technical '
          'decisions, knowing the source is genuinely useful.',
      'Speed is the only priority \u2014 for trivial, reversible '
          'decisions, anonymous processes add unnecessary overhead.',
    ]),
    BlogParagraph(
      'The key insight is matching the process to the stakes. '
      'High-stakes decisions where buy-in matters and power dynamics '
      'exist? That\u2019s exactly where an anonymous decision making '
      'tool for teams earns its value.',
    ),
    BlogDivider(),

    // Practical Tips
    BlogHeading('Making the Shift: Practical Tips'),
    BlogSubheading('Start with a real decision, not a test'),
    BlogParagraph(
      'Don\u2019t pilot anonymous decision making on something trivial. '
      'Pick a decision that actually matters \u2014 one where you\u2019ve '
      'experienced the dynamics described in this article.',
    ),
    BlogSubheading('Explain the why'),
    BlogParagraph(
      'Be direct with your team: \u201cWe\u2019re trying anonymous '
      'proposals because I want everyone\u2019s ideas to compete on '
      'merit, not on who said them.\u201d Most people respond well to '
      'that framing.',
    ),
    BlogSubheading('Commit to the outcome'),
    BlogParagraph(
      'If the group converges on an answer and the manager vetoes it, '
      'you\u2019ve destroyed trust in the process permanently. Before '
      'you start, decide whether you\u2019ll genuinely honor the '
      'group\u2019s outcome.',
    ),
    BlogDivider(),

    // CTA
    BlogHeading('Try Bias-Free Decision Making with OneMind'),
    BlogParagraph(
      'OneMind is a free consensus-building app that automates the '
      'entire structured convergence process. Groups propose ideas '
      'anonymously, rate them fairly, and repeat rounds until one idea '
      'wins back-to-back \u2014 real convergence, not forced compromise.',
    ),
    BlogParagraph(
      'No accounts required. No downloads. Works on any device with '
      'a browser. Your team can run its first anonymous decision in '
      'under five minutes.',
    ),
    BlogCta(
      text: 'If you\u2019ve ever left a meeting thinking \u201cwe '
          'didn\u2019t pick the best idea \u2014 we just picked the '
          'loudest one,\u201d OneMind is built for you.',
      buttonLabel: 'Try OneMind Free',
      route: '/tutorial',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Post 2: Voting vs. Consensus
// ---------------------------------------------------------------------------

const _votingVsConsensus = BlogPost(
  slug: 'voting-vs-consensus',
  title: 'Voting vs. Consensus: Why Your Team Gets Stuck '
      'and How to Actually Align',
  metaDescription:
      'Voting creates winners and losers. Traditional consensus takes '
      'forever. Learn why both fail teams and discover a third approach '
      'that finds real alignment \u2014 fast.',
  date: '2026-03-24',
  author: 'Joel Castro',
  keywords: [
    'voting vs consensus',
    'consensus vs voting',
    'consensus decision making',
    'how to build consensus in a team',
    'alternatives to majority voting',
  ],
  sections: [
    BlogParagraph(
      'Your team has a decision to make. Someone suggests, '
      '\u201cLet\u2019s just vote on it.\u201d',
    ),
    BlogParagraph(
      'It sounds democratic. It sounds fast. But voting is often where '
      'alignment goes to die.',
    ),
    BlogParagraph(
      'Here\u2019s why \u2014 and what actually works instead.',
    ),
    BlogDivider(),

    // The Problem with Voting
    BlogHeading('The Problem with Voting'),
    BlogParagraph(
      'Voting feels fair. Everyone gets a say, majority rules. But in '
      'practice, voting has three critical flaws:',
    ),
    BlogSubheading('It creates losers'),
    BlogParagraph(
      'If the vote is 6-4, those four people didn\u2019t just lose a '
      'preference \u2014 they lost influence. They walk away feeling '
      'unheard. Over time, this breeds quiet disengagement or outright '
      'resentment.',
    ),
    BlogSubheading('It rewards framing, not ideas'),
    BlogParagraph(
      'You can only vote on what\u2019s presented. Whoever controls the '
      'options controls the outcome. This is why experienced politicians '
      'spend more energy framing the question than answering it.',
    ),
    BlogSubheading('It stops thinking too early'),
    BlogParagraph(
      'Once you vote, the decision is \u201cdone.\u201d There\u2019s '
      'no mechanism for an initial minority position to prove itself '
      'stronger over time. The best idea might have lost because it was '
      'unfamiliar, not because it was wrong.',
    ),
    BlogDivider(),

    // The Problem with Traditional Consensus
    BlogHeading('The Problem with Traditional Consensus'),
    BlogParagraph(
      'Frustrated by voting, some teams swing to the opposite extreme: '
      '\u201cWe won\u2019t decide until everyone agrees.\u201d',
    ),
    BlogParagraph(
      'This sounds noble but creates its own problems:',
    ),
    BlogSubheading('It takes forever'),
    BlogParagraph(
      'One person\u2019s hesitation can block the entire group. '
      'Discussions spiral as the team tries to accommodate every concern.',
    ),
    BlogSubheading('Silence gets mistaken for agreement'),
    BlogParagraph(
      'When the facilitator asks \u201cDoes anyone object?\u201d, '
      'social pressure kicks in. People stay quiet to avoid being the '
      'blocker \u2014 even when they have genuine concerns.',
    ),
    BlogSubheading('It produces watered-down compromises'),
    BlogParagraph(
      'To get everyone on board, the decision gets edited until it\u2019s '
      'the least objectionable option rather than the best one. Nobody '
      'hates it, but nobody loves it either.',
    ),
    BlogDivider(),

    // Why Teams Get Stuck
    BlogHeading('Why Teams Get Stuck'),
    BlogParagraph(
      'The real problem isn\u2019t voting OR consensus. It\u2019s the '
      'assumption that these are the only two options.',
    ),
    BlogParagraph(
      'Most teams operate in a cycle: they try discussion-then-voting, '
      'get frustrated with the winners/losers dynamic, switch to '
      'consensus-seeking, get frustrated with how long it takes, and '
      'swing back to voting. Neither approach addresses the root cause.',
    ),
    BlogParagraph(
      'The root cause is this: in both models, WHO says something '
      'matters as much as WHAT they say. The manager\u2019s suggestion '
      'carries more weight. The loudest voice gets more airtime. The '
      'first idea anchors the discussion. These are not personality '
      'problems \u2014 they\u2019re structural problems baked into '
      'the process.',
    ),
    BlogDivider(),

    // The Third Option
    BlogHeading('The Third Option: Structured Convergence'),
    BlogParagraph(
      'What if you could get the speed of voting with the alignment of '
      'consensus \u2014 without the downsides of either?',
    ),
    BlogParagraph(
      'That\u2019s what structured convergence does. Here\u2019s how '
      'it works:',
    ),
    BlogSubheading('Anonymous proposing'),
    BlogParagraph(
      'Instead of discussing ideas out loud (where hierarchy and '
      'confidence bias the conversation), everyone submits ideas '
      'anonymously. This one structural change eliminates most of the '
      'dysfunction in group decision-making.',
    ),
    BlogSubheading('Fair rating'),
    BlogParagraph(
      'Instead of a binary vote, everyone rates every idea on a scale. '
      'This captures nuance that up/down voting misses. An idea that\u2019s '
      'everyone\u2019s second choice (but nobody\u2019s first) might '
      'actually be the strongest consensus pick.',
    ),
    BlogSubheading('Multiple rounds'),
    BlogParagraph(
      'Unlike a one-shot vote, ideas compete across rounds. The '
      'highest-rated ideas carry forward. When the same idea wins '
      'repeatedly, that\u2019s convergence \u2014 genuine alignment, '
      'not forced agreement.',
    ),
    BlogParagraph(
      'This approach works because it separates idea quality from social '
      'dynamics. The best idea wins regardless of who proposed it, how '
      'confidently they speak, or where they sit in the org chart.',
    ),
    BlogDiagram(),
    BlogDivider(),

    // When to Use Which
    BlogHeading('When to Use Which Approach'),
    BlogParagraph(
      'Not every decision needs structured convergence. Here\u2019s '
      'a practical guide:',
    ),
    BlogBulletList([
      'Use voting when the decision is low-stakes, reversible, or the '
          'group has no strong feelings. \u201cWhat should we order for '
          'lunch?\u201d doesn\u2019t need a consensus process.',
      'Use traditional consensus when the group is small (3\u20135 '
          'people), trusts each other deeply, and has unlimited time. '
          'Co-founder decisions, for example, often work well with '
          'open consensus.',
      'Use structured convergence when the decision matters, the group '
          'is larger than 5, there are power dynamics at play, or you '
          'need people to genuinely support the outcome \u2014 not '
          'just tolerate it.',
    ]),
    BlogCta(
      text: 'OneMind automates the entire structured convergence process '
          '\u2014 anonymous proposals, fair rating, multi-round '
          'convergence \u2014 in your browser. No accounts, no downloads.',
      buttonLabel: 'Try OneMind Free',
      route: '/tutorial',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Post 1: Group Decision Making Methods
// ---------------------------------------------------------------------------

const _groupDecisionMakingMethods = BlogPost(
  slug: 'group-decision-making-methods',
  title: '5 Group Decision-Making Methods That Actually Work '
      '(And When to Use Each)',
  metaDescription:
      'Compare 5 proven group decision-making techniques — from majority '
      'voting to structured consensus. Learn which method fits your team '
      'and when to use each one.',
  date: '2026-03-24',
  author: 'Joel Castro',
  keywords: [
    'group decision making techniques',
    'group decision making methods',
    'team decision making process',
    'how to make group decisions',
    'consensus building techniques',
  ],
  sections: [
    BlogParagraph(
      'Every team makes group decisions. Most do it badly.',
    ),
    BlogParagraph(
      'The default approach \u2014 whoever talks the most in the meeting '
      'wins \u2014 wastes time, frustrates quiet team members, and '
      'produces decisions nobody fully supports. But it doesn\u2019t '
      'have to be this way.',
    ),
    BlogParagraph(
      'Here are five group decision-making methods, ranked from simplest '
      'to most effective, with honest trade-offs for each.',
    ),
    BlogDivider(),

    // 1. Majority Voting
    BlogHeading('1. Majority Voting'),
    BlogSubheading('How it works'),
    BlogParagraph(
      'Everyone votes. The option with more than 50% wins.',
    ),
    BlogSubheading('Best for'),
    BlogParagraph(
      'Low-stakes decisions with clear binary options (\u201cDo we '
      'move the meeting to Tuesday or Thursday?\u201d).',
    ),
    BlogSubheading('The problem'),
    BlogParagraph(
      'Voting creates winners and losers. The 49% who voted differently '
      'feel unheard. It also rewards whoever frames the options \u2014 '
      'you can only vote on what\u2019s put in front of you. For '
      'important decisions, this breeds resentment, not alignment.',
    ),
    BlogDivider(),

    // 2. Dot Voting
    BlogHeading('2. Dot Voting (Multi-Voting)'),
    BlogSubheading('How it works'),
    BlogParagraph(
      'Each person gets a fixed number of \u201cdots\u201d (votes) to '
      'distribute across options. Options with the most dots rise '
      'to the top.',
    ),
    BlogSubheading('Best for'),
    BlogParagraph(
      'Narrowing down a large list of ideas (e.g., brainstorming '
      'sessions, sprint planning).',
    ),
    BlogSubheading('The problem'),
    BlogParagraph(
      'It\u2019s still a popularity contest, just with more granularity. '
      'Anchoring bias is real \u2014 the first ideas presented or the '
      'ones from senior people tend to get more dots. And it still '
      'doesn\u2019t tell you WHY people prefer something.',
    ),
    BlogDivider(),

    // 3. Delphi Method
    BlogHeading('3. Delphi Method'),
    BlogSubheading('How it works'),
    BlogParagraph(
      'Experts answer questions individually and anonymously across '
      'multiple rounds. After each round, results are shared and '
      'experts revise their answers. Over rounds, opinions converge.',
    ),
    BlogSubheading('Best for'),
    BlogParagraph(
      'Complex forecasting or technical decisions where expertise '
      'matters more than politics.',
    ),
    BlogSubheading('The problem'),
    BlogParagraph(
      'It\u2019s slow (days to weeks), requires a dedicated '
      'facilitator, and works best with domain experts \u2014 not '
      'everyday team decisions. Most teams don\u2019t have the '
      'patience or structure to run it.',
    ),
    BlogDivider(),

    // 4. Consent-Based
    BlogHeading('4. Consent-Based Decision Making (Sociocracy)'),
    BlogSubheading('How it works'),
    BlogParagraph(
      'Instead of asking \u201cDoes everyone agree?\u201d, you ask '
      '\u201cDoes anyone have a principled objection?\u201d If no one '
      'objects, the decision passes.',
    ),
    BlogSubheading('Best for'),
    BlogParagraph(
      'Organizations that want to move fast while respecting dissent. '
      'Common in co-ops, non-profits, and agile teams.',
    ),
    BlogSubheading('The problem'),
    BlogParagraph(
      '\u201cNo objection\u201d isn\u2019t the same as genuine support. '
      'People stay silent for many reasons \u2014 social pressure, '
      'fatigue, not wanting to be \u201cthat person.\u201d You can end '
      'up with decisions that nobody actively opposes but nobody truly '
      'believes in either.',
    ),
    BlogDivider(),

    // 5. Structured Convergence
    BlogHeading('5. Structured Convergence (Anonymous Proposing + '
        'Iterative Rating)'),
    BlogSubheading('How it works'),
    BlogParagraph(
      'Everyone proposes ideas anonymously. The group rates every idea. '
      'Top ideas carry forward to the next round. When the same idea '
      'wins multiple rounds, that\u2019s convergence \u2014 the '
      'group\u2019s genuine answer.',
    ),
    BlogSubheading('Best for'),
    BlogParagraph(
      'Any decision where you need real buy-in, not just compliance. '
      'Works for remote teams, large groups, and politically '
      'sensitive topics.',
    ),
    BlogSubheading('Why it works'),
    BlogParagraph(
      'Anonymous proposals remove bias \u2014 ideas are judged on merit, '
      'not who said them. Multiple rounds force the group to genuinely '
      'evaluate rather than just react. And because the process is '
      'transparent and fair, people trust the outcome even when their '
      'idea didn\u2019t win.',
    ),
    BlogParagraph(
      'This is the approach that OneMind is built on.',
    ),
    BlogDiagram(),
    BlogCta(
      text: 'Try structured convergence with your team \u2014 free, '
          'no account needed.',
      buttonLabel: 'Try OneMind Free',
      route: '/tutorial',
    ),
    BlogDivider(),

    // Summary
    BlogHeading('Which Method Should You Use?'),
    BlogParagraph('Quick rule of thumb:'),
    BlogBulletList([
      'Binary, low-stakes? \u2192 Majority vote',
      'Narrowing a long list? \u2192 Dot voting',
      'Expert forecasting? \u2192 Delphi method',
      'Need to move fast with no blockers? \u2192 Consent-based',
      'Need genuine alignment on important decisions? \u2192 '
          'Structured convergence',
    ]),
    BlogParagraph(
      'The key insight is that most teams default to discussion + '
      'voting for EVERYTHING, when it\u2019s actually the worst fit '
      'for their most important decisions. The more a decision matters, '
      'the more structure you need in the process.',
    ),
    BlogCta(
      text: 'Ready to try structured convergence? OneMind runs the '
          'entire process \u2014 anonymous proposals, fair rating, '
          'multi-round convergence \u2014 in your browser.',
      buttonLabel: 'Start for Free',
      route: '/tutorial',
    ),
  ],
);
