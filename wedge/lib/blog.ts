export type BlogSection =
  | { type: "paragraph"; text: string }
  | { type: "heading"; text: string }
  | { type: "subheading"; text: string }
  | { type: "bullets"; items: string[] }
  | { type: "cta"; text: string; buttonLabel: string; route: string }
  | { type: "divider" }
  | { type: "diagram" };

export type BlogPost = {
  slug: string;
  title: string;
  metaDescription: string;
  date: string;
  author: string;
  keywords: string[];
  sections: BlogSection[];
};

// Ported verbatim from lib/screens/blog/blog_data.dart. Order = newest first,
// matching the Dart `blogPosts` list order.
export const blogPosts: BlogPost[] = [
  // -------------------------------------------------------------------------
  // Post 5: Communities Solving Real Problems (_citiesCollectiveIntelligence)
  // -------------------------------------------------------------------------
  {
    slug: "communities-solve-real-problems-together",
    title:
      "From Bullying Prevention to Urban Planning: How Communities Solve Real Problems Together",
    metaDescription:
      "OneMind isn't for formal government—it's for real people solving problems they care about. See how communities are using collective intelligence to tackle bullying, urban challenges, education, and more.",
    date: "2026-05-09",
    author: "Joel Castro",
    keywords: [
      "community problem solving",
      "collective intelligence",
      "civic engagement",
      "grassroots solutions",
      "community consensus",
      "participatory decision making",
      "social problem solving",
    ],
    sections: [
      { type: "heading", text: "The Real Problems Don't Wait for Permission" },
      {
        type: "paragraph",
        text: "A person struggling with bullying doesn't schedule a city council meeting. They look for people who understand. A neighborhood annoyed by car traffic in their downtown doesn't file a formal petition. They start a conversation with neighbors. A student wondering how universities could use collective intelligence doesn't wait for administration approval. They invite others to think alongside them.",
      },
      {
        type: "paragraph",
        text: "This is how real communities solve problems: people who care, thinking together, until they converge on something better.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Real Problems OneMind Communities Are Tackling",
      },
      { type: "subheading", text: "Personal & Social" },
      {
        type: "paragraph",
        text: '"Best way to survive bullying" — five people working through one of the loneliest experiences, sharing wisdom. Not a support group, not therapy. Collective problem-solving on how to actually survive and move forward. Everyone stays anonymous, and ideas are sorted by head-to-head voting so the strongest rise to the top on merit. By the end, the group has built something stronger than any one person could have alone.',
      },
      { type: "subheading", text: "Urban & Environmental" },
      {
        type: "paragraph",
        text: '"Should downtown areas ban car traffic to improve quality of life and reduce accidents?" Eight people debating the real trade-offs. City planners don\'t need to ask permission—they can surface what actual residents would converge on.',
      },
      { type: "subheading", text: "Educational" },
      {
        type: "paragraph",
        text: '"How do you imagine OneMind being used in universities?" Nine people—likely some students, some educators—collectively designing what civic engagement could look like on campus. No committee. No budget approval. Just thinking together about what\'s possible.',
      },
      { type: "subheading", text: "Cultural & Information" },
      {
        type: "paragraph",
        text: '"How can media literacy be improved?" Six people exploring why people believe misinformation and what actually helps. "How can music artists fight the algorithm?" People thinking through real creative problems. These aren\'t theoretical exercises—they\'re practical thinking on issues people actually care about.',
      },
      { type: "subheading", text: "Existential & Philosophical" },
      {
        type: "paragraph",
        text: '"Do you believe AI can replace human beings?" Not an academic debate. Seven people genuinely wrestling with what makes us irreplaceable. "What\'s the #1 problem facing society today?" The group collectively surfaces what they think matters most.',
      },
      { type: "divider" },

      { type: "heading", text: "Why Grassroots Problem-Solving Works" },
      { type: "subheading", text: "Everyone who shows up actually cares" },
      {
        type: "paragraph",
        text: "You don't get people joining a OneMind conversation to fulfill an obligation. They show up because the problem matters to them. That self-selection creates a different kind of participation—authentic, engaged, inventive.",
      },
      { type: "subheading", text: "Ideas evolve through real thinking" },
      {
        type: "paragraph",
        text: "As people vote head-to-head on each other's anonymous ideas, thinking refines. The first idea on bullying survival might focus on emotional resilience. Reply to it and that reply opens its own ranked thread — practical steps, community, self-compassion — nested as deep as the problem needs. The problem-solving *deepens*.",
      },
      { type: "subheading", text: "Consensus on solutions is real" },
      {
        type: "paragraph",
        text: 'When the idea emphasizing "protected pedestrian zones + transit investment" keeps winning its head-to-head matchups on car traffic, it rises to the top on merit. Not because an authority decided it. Because the community\'s own voting ranked it there.',
      },
      { type: "subheading", text: "The solution is locally informed" },
      {
        type: "paragraph",
        text: "A bullying survivor knows something a psychologist might not. A downtown resident knows traffic patterns a planner doesn't. Anonymous head-to-head voting surfaces that embodied knowledge and weighs it equally with every other perspective — ideas rise on merit, not on who holds the credential.",
      },
      { type: "divider" },

      { type: "heading", text: "What This Means for Communities" },
      {
        type: "paragraph",
        text: "You don't need a formal process to solve problems together. You don't need committee approval or budget lines. You need:",
      },
      {
        type: "bullets",
        items: [
          "A problem that matters to a group of people",
          "A way for everyone to propose solutions anonymously",
          "A fair way to evaluate all ideas",
          "Head-to-head voting that ranks every idea on merit, not on who said it",
          "Threads that branch without limit, so the best thinking rises to the top",
        ],
      },
      {
        type: "paragraph",
        text: "OneMind provides that structure. You provide the people and the problem.",
      },
      { type: "divider" },

      { type: "heading", text: "Start Where You Are" },
      {
        type: "paragraph",
        text: "You don't need to wait for the right infrastructure, the right committee, or the right permission. If you're facing a problem and you know others who care, you can start thinking together right now.",
      },
      {
        type: "paragraph",
        text: "A bullying survivor can create a chat. A neighborhood can converge on traffic solutions. Students can reimagine university culture. Communities can define their own solutions.",
      },
      { type: "divider" },

      { type: "heading", text: "Solve Real Problems with Your Community" },
      {
        type: "paragraph",
        text: "Start a OneMind conversation about a problem you care about. Invite people who understand it. Let anonymous head-to-head voting surface the solutions your community actually ranks highest — the best rising to the top on merit.",
      },
      {
        type: "cta",
        text: 'If you\'ve ever thought "we could solve this if everyone just contributed their real thinking," OneMind is built for that moment.',
        buttonLabel: "Start a Chat",
        route: "/tutorial",
      },
    ],
  },

  // -------------------------------------------------------------------------
  // Post 6: Philosophical Alignment (_participatoryDemocracyDigital)
  // -------------------------------------------------------------------------
  {
    slug: "philosophical-alignment-converge-meaning",
    title: "Philosophical Alignment: How Strangers Converge on Meaning",
    metaDescription:
      "The hardest conversations are about values, not logistics. See how anonymous, head-to-head voting ranks ideas on merit so strangers converge on meaning and open-ended questions.",
    date: "2026-05-09",
    author: "Joel Castro",
    keywords: [
      "collective intelligence",
      "group consensus building",
      "philosophical discussion",
      "values alignment",
      "meaning-making",
      "existential questions",
      "community convergence",
    ],
    sections: [
      { type: "heading", text: "The Hardest Decisions Aren't Binary" },
      {
        type: "paragraph",
        text: 'Every organization faces moments when the real question isn\'t "Which option should we pick?" but "Who are we becoming?" and "What do we actually believe?"',
      },
      {
        type: "paragraph",
        text: "A startup deciding whether to pivot. A community group wrestling with values. A team asking what success actually means. These conversations resist traditional decision-making tools because there's no binary choice, no clear winner, no spreadsheet that resolves the tension.",
      },
      {
        type: "paragraph",
        text: "Yet these are the conversations that matter most. And they're also the ones where OneMind shines—not because it forces agreement, but because anonymous head-to-head voting lets real thinking rise on its merit.",
      },
      { type: "divider" },

      { type: "heading", text: "Why Philosophical Alignment Is Different" },
      {
        type: "paragraph",
        text: 'Most decision-making frameworks assume a fixed menu of options. You rank them, vote on them, debate their trade-offs. But open-ended questions—"What should we become?" "What matters most?" "How do we navigate this ethical dilemma?"—don\'t work that way.',
      },
      { type: "subheading", text: "The problem with discussion" },
      {
        type: "paragraph",
        text: "In a room full of smart people, whoever speaks first anchors the conversation. The loudest voice shapes the frame. Quiet people think deeper but speak less. By the end, you don't have genuine alignment—you have whoever talked the most framing it as alignment.",
      },
      { type: "subheading", text: "The problem with voting" },
      {
        type: "paragraph",
        text: "Voting assumes you know what you're choosing between. But in philosophical conversations, you're often figuring out the options *as you think*. Someone else's proposal might illuminate something you hadn't considered. Early voting locks in half-formed positions.",
      },
      { type: "subheading", text: "The problem with consensus-seeking" },
      {
        type: "paragraph",
        text: 'Waiting for everyone to agree on abstract values can take forever. And "consensus" often means "we stopped disagreeing because we\'re tired," not "we actually converged."',
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Real Examples: How Convergence Surfaces Alignment",
      },
      {
        type: "paragraph",
        text: "The most powerful OneMind conversations aren't about logistics. They're about meaning.",
      },
      {
        type: "subheading",
        text: '"Do you believe AI can replace human beings?"',
      },
      {
        type: "paragraph",
        text: 'Seven people, no clear stakes, pure intellectual exploration. The question forces participants to examine what they think is irreplaceable about humans. As people vote head-to-head on each other\'s anonymous ideas, the strongest rise. Early ideas might emphasize emotion or creativity. Reply to one and that reply opens its own ranked thread, synthesizing further: "AI can replace tasks, but consciousness and intention are different." By the end, the group has moved together toward a shared understanding.',
      },
      { type: "subheading", text: '"What should OneMind become?"' },
      {
        type: "paragraph",
        text: "1,273 people. No executives, no predetermined answer. The group submitted 155+ anonymous ideas and sorted them by voting head-to-head. The ideas that kept winning their matchups rose to the top on merit—all emphasizing collective wisdom, merit over hierarchy, and honest dialogue. The process didn't impose those values. It *surfaced* them.",
      },
      { type: "subheading", text: '"Make the universe friend"' },
      {
        type: "paragraph",
        text: "Nineteen people exploring existential connection. The title is deliberately abstract. Participants propose their interpretation—community as antidote to loneliness, universal empathy, shared purpose. No one \"wins.\" Instead, the group converges toward a shared vision of belonging.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Why Merit-Ranked Voting Works for Philosophy",
      },
      { type: "subheading", text: "Ideas compete on merit" },
      {
        type: "paragraph",
        text: "In a single meeting, you defend your initial position. On OneMind, every idea is anonymous and sorted by head-to-head voting—you see which ideas win their matchups, read the ones ranked above yours, and reply to any of them to open a new thread. You build something stronger not because you were wrong, but because you learned something. Philosophy is collaborative thinking, not debate.",
      },
      { type: "subheading", text: "Anonymous proposals remove ego" },
      {
        type: "paragraph",
        text: "When you're thinking about consciousness, meaning, or ethics, you want to engage with the idea, not the person. Anonymity lets a junior team member's insight compete equally with a CEO's perspective. It lets shy people think out loud without social risk.",
      },
      { type: "subheading", text: "Head-to-head voting captures nuance" },
      {
        type: "paragraph",
        text: 'An idea might not top the ranking, but still win most of its direct matchups. Because position comes from how often an idea beats others head-to-head—judged by everyone, like Elo—the ranking reflects a real distribution of the group\'s values, not forced uniformity.',
      },
      { type: "subheading", text: "Convergence means real alignment" },
      {
        type: "paragraph",
        text: "When one vision keeps winning its head-to-head matchups and rises to the top, people feel it. They didn't settle. They didn't get talked into it. They genuinely came to the same place through their own thinking, refined by exposure to others.",
      },
      { type: "divider" },

      { type: "heading", text: "When to Use Convergence for Meaning-Making" },
      {
        type: "paragraph",
        text: "This kind of anonymous, merit-ranked conversation is ideal for:",
      },
      {
        type: "bullets",
        items: [
          "Defining organizational values or mission (What do we actually stand for?)",
          "Navigating ethical dilemmas (What's the right call here?)",
          "Exploring existential or philosophical questions (Who are we? What matters?)",
          "Building shared vision during transformation (What are we becoming?)",
          "Cross-cultural or cross-generational understanding (How do we bridge this divide?)",
          "Community identity work (What does this community value?)",
        ],
      },
      { type: "divider" },

      {
        type: "heading",
        text: "The Gift of Convergence: Alignment Without Uniformity",
      },
      {
        type: "paragraph",
        text: "Philosophical alignment doesn't mean everyone ends up identical. It means everyone has been genuinely heard, everyone has thought carefully, and everyone recognizes the final direction as *legitimate*—even if it's not their first choice.",
      },
      {
        type: "paragraph",
        text: "That's rare. That's powerful. And it's what happens when you give a group the right structure for collective thinking.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Explore Philosophical Convergence with OneMind",
      },
      {
        type: "paragraph",
        text: "Start a conversation about something that matters to your community. No right answers. No predetermined options. Just people thinking together until alignment emerges.",
      },
      {
        type: "cta",
        text: "If you've ever struggled to build genuine alignment on values, vision, or meaning—where people's actual thinking matters—OneMind is built for that conversation.",
        buttonLabel: "Start a Conversation",
        route: "/tutorial",
      },
    ],
  },

  // -------------------------------------------------------------------------
  // Post 4: Async Decision Making (_asyncDecisionMaking)
  // -------------------------------------------------------------------------
  {
    slug: "async-decision-making-remote-teams",
    title:
      "Think Together Honestly: Async Decision Making for Distributed Communities",
    metaDescription:
      "Discover better solutions than any one person could create alone. Learn how asynchronous decision making enables people from different backgrounds to refine each other's ideas and reach genuine collective consensus.",
    date: "2026-03-27",
    author: "Joel Castro",
    keywords: [
      "async decision making tools for communities",
      "asynchronous decision making",
      "distributed community decisions",
      "participatory democracy tools",
      "global participation platform",
      "civic engagement decision making",
    ],
    sections: [
      {
        type: "heading",
        text: "The Meeting That Could Have Been an Email — And the Email That Solved Nothing",
      },
      {
        type: "paragraph",
        text: "It’s 8 AM in New York. Your engineering lead in Berlin has been online for six hours. Your designer in Tokyo already signed off. And someone just scheduled a “quick alignment call” for 4 PM UTC — which is dinner time in Berlin, midnight in Tokyo, and right in the middle of deep work for New York.",
      },
      {
        type: "paragraph",
        text: "The call happens anyway. Half the team attends live. The rest watch a recording three days later and reply with comments that nobody reads because the decision already got made by whoever showed up.",
      },
      {
        type: "paragraph",
        text: "This is the default decision-making process for most distributed teams. And it’s broken in ways that “better meeting hygiene” can’t fix.",
      },
      {
        type: "paragraph",
        text: "The problem isn’t that your team needs better meetings. It’s that synchronous decision making fundamentally doesn’t work when your team spans time zones, schedules, and working styles. What you need are async decision making tools for remote teams — approaches that let people contribute their best thinking on their own time, then converge on an answer everyone can support.",
      },
      { type: "divider" },

      { type: "heading", text: "Why Synchronous Decisions Fail Remote Teams" },
      {
        type: "subheading",
        text: "Time zone math is a tax on participation",
      },
      {
        type: "paragraph",
        text: "For a team spanning three or more time zones, there is no “good” meeting time. Someone is always attending at an inconvenient hour. Over time, the people in the “wrong” time zone participate less, contribute less, and quietly disengage from decisions that affect their work.",
      },
      { type: "subheading", text: "Meetings reward presence, not quality" },
      {
        type: "paragraph",
        text: "In a live meeting, the people who happen to be alert, prepared, and comfortable speaking up have outsized influence. The loudest voice in the room often wins — not because their idea is best, but because the process rewards confidence over substance. This problem compounds remotely, where connection issues and camera fatigue further skew who gets heard.",
      },
      { type: "subheading", text: "Recordings don’t equal participation" },
      {
        type: "paragraph",
        text: "Teams try to solve the timezone problem by recording meetings. But watching a 45-minute recording is passive consumption, not participation. By the time someone comments, the group has moved on.",
      },
      { type: "subheading", text: "Decision fatigue multiplied" },
      {
        type: "paragraph",
        text: "Remote workers attend more meetings than their in-office counterparts. Each meeting demands a context switch, draining the cognitive energy that would have produced better thinking in an asynchronous format.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Async Approaches: The Promise and the Limits",
      },
      { type: "subheading", text: "Slack polls and emoji votes" },
      {
        type: "paragraph",
        text: "The most common async “decision tool” for remote teams is a Slack poll or emoji reaction. Someone posts a question, people react, the most popular emoji wins.",
      },
      {
        type: "bullets",
        items: [
          "Pros: Zero friction, everyone knows how to use it, instant results.",
          "Cons: Whoever writes the poll controls the options. No nuance. Early votes anchor later ones. No mechanism for ideas to evolve.",
        ],
      },
      { type: "subheading", text: "Email and document threads" },
      {
        type: "paragraph",
        text: "Someone writes a proposal in a Google Doc or email, and the team comments. This gives everyone time to think and respond.",
      },
      {
        type: "bullets",
        items: [
          "Pros: Asynchronous by nature, supports long-form thinking, creates a paper trail.",
          "Cons: Threads fracture. Loud voices still dominate via word count. No clear mechanism to resolve disagreement. Decisions stall in “still discussing” limbo.",
        ],
      },
      { type: "subheading", text: "Dedicated async tools (Loomio, Range)" },
      {
        type: "paragraph",
        text: "Purpose-built tools offer structured proposals with voting, threads, and deadlines. A step up from Slack polls, but most still rely on voting mechanics with their well-documented limitations. Proposals are tied to names, introducing bias. One-round voting means the group commits before ideas have been stress-tested.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "What Effective Async Decision Making Actually Needs",
      },
      {
        type: "bullets",
        items: [
          "Equal access: Everyone participates on their own schedule, regardless of time zone.",
          "Anonymous input: Ideas compete on merit, not on who proposed them.",
          "Merit-based evaluation: not thumbs-up/thumbs-down, but head-to-head voting that ranks every idea by how often it wins direct comparisons.",
          "Branching: any idea can be replied to, opening its own ranked thread, so thinking deepens instead of locking in after a single vote.",
          "Clear resolution: A defined endpoint so decisions don’t languish in “open” status indefinitely.",
        ],
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Self-Ranking Conversations: The Missing Async Decision Making Tool for Remote Teams",
      },
      {
        type: "paragraph",
        text: "A self-ranking conversation — anonymous ideas sorted by head-to-head voting, branching into threads — turns out to be naturally asynchronous. It works better async than sync, because it was designed around written contributions rather than verbal debate.",
      },
      { type: "subheading", text: "Step 1: Everyone proposes on their own time" },
      {
        type: "paragraph",
        text: "A question goes out to the group. Each person submits their proposed answer anonymously within a time window — hours or days, not minutes. Your Tokyo team member contributes during their morning. Your Berlin lead adds theirs after lunch. Nobody missed the meeting because there was no meeting.",
      },
      { type: "subheading", text: "Step 2: Everyone votes head-to-head" },
      {
        type: "paragraph",
        text: "Each participant is shown two ideas at a time and picks the stronger. An idea’s position comes from how often it wins these direct comparisons, judged by everyone—like Elo, not likes or upvotes. Because ideas are anonymous, every judgment is based purely on substance.",
      },
      { type: "subheading", text: "Step 3: The best rise to the top" },
      {
        type: "paragraph",
        text: "Ideas sort themselves into a live, merit-ranked list—the strongest at the top. Anyone can reply to any idea, and that reply opens its own ranked thread, so the conversation branches without limit instead of flattening into one vote.",
      },
      { type: "subheading", text: "Step 4: The ranking is your answer" },
      {
        type: "paragraph",
        text: "The idea that keeps winning its head-to-head matchups sits at the top—genuine group alignment, arrived at on merit. The entire process happens asynchronously. No scheduling conflicts. No time zone math.",
      },
      { type: "diagram" },
      { type: "divider" },

      {
        type: "heading",
        text: "Real-World Examples: Async Decisions in Practice",
      },
      {
        type: "subheading",
        text: "Distributed engineering team: Quarterly priorities",
      },
      {
        type: "paragraph",
        text: "A 15-person engineering team across San Francisco, London, and Singapore needs to decide which technical debt to tackle in Q3. With OneMind, all 15 engineers submit anonymous ideas during their regular hours and vote head-to-head on them. Because ranking comes from direct comparisons, the Singapore team’s input carries equal weight. Over three days, a database migration rises to the top—one the architects hadn’t prioritized but the team collectively ranked as the biggest bottleneck.",
      },
      {
        type: "subheading",
        text: "Cross-timezone committee: Nonprofit policy update",
      },
      {
        type: "paragraph",
        text: "A global nonprofit’s advisory committee spans six time zones. Instead of three weeks of calendar coordination, they post the policy question with a 48-hour window for anonymous ideas and head-to-head voting. The idea that wins the most direct matchups rises to the top, incorporating perspectives from every region. Total time per participant: under 30 minutes.",
      },
      {
        type: "subheading",
        text: "Hybrid organization: Product roadmap",
      },
      {
        type: "paragraph",
        text: "A 40-person company with half the team remote faces a persistent problem: in-office employees dominate roadmap decisions via hallway conversations. Anonymous, merit-ranked voting levels the field. Every team member submits feature proposals anonymously. The roadmap reflects the genuine priorities of the entire team, not just those with physical proximity to decision-makers.",
      },
      { type: "divider" },

      { type: "heading", text: "When Async Isn’t the Right Call" },
      {
        type: "bullets",
        items: [
          "Crisis response: If the server is down, you need a war room, not an async poll.",
          "Relationship building: Some meetings exist for trust and rapport, not decisions.",
          "Creative brainstorming: Live riffing has genuine value for early-stage ideation.",
          "Very small, high-trust teams: A three-person founding team probably doesn’t need formal async structure.",
        ],
      },
      { type: "divider" },

      { type: "heading", text: "Making the Shift: Practical Tips" },
      { type: "subheading", text: "Audit your meetings first" },
      {
        type: "paragraph",
        text: "Which recurring meetings exist primarily to make decisions? For each one, ask: “Could this decision be made better if everyone had time to think before responding?” If yes, that meeting is a candidate for async conversion.",
      },
      { type: "subheading", text: "Set explicit time windows" },
      {
        type: "paragraph",
        text: "Instead of “respond by Friday,” try “proposing window: Tuesday 9 AM to Thursday 9 AM UTC.” Time windows give every time zone a full working day to participate.",
      },
      { type: "subheading", text: "Separate proposing from evaluating" },
      {
        type: "paragraph",
        text: "Let everyone submit ideas first. Then evaluate as a separate step. This prevents anchoring — the first idea posted in a Slack thread no longer sets the frame for everything after.",
      },
      { type: "subheading", text: "Make anonymity the default" },
      {
        type: "paragraph",
        text: "Remote teams have invisible power dynamics: the person in the CEO’s time zone, the one who responds fastest in Slack. Anonymous proposing and rating neutralize all of these.",
      },
      { type: "divider" },

      { type: "heading", text: "Try Async Decision Making with OneMind" },
      {
        type: "paragraph",
        text: "OneMind is a free app built for exactly this problem. Everyone's anonymous—groups submit ideas, vote on them head-to-head, and the best rise to the top on merit, all asynchronously. No scheduling. No time zone math. No meetings.",
      },
      {
        type: "cta",
        text: "If your team is tired of meetings that don’t decide anything and Slack polls that oversimplify everything, OneMind is the async decision making tool built for how remote teams actually work.",
        buttonLabel: "Try OneMind Free",
        route: "/tutorial",
      },
    ],
  },

  // -------------------------------------------------------------------------
  // Post 3: Anonymous Decision Making (_anonymousDecisionMaking)
  // -------------------------------------------------------------------------
  {
    slug: "anonymous-decision-making",
    title:
      "Quality Matters More Than Source: Why Anonymous Decision Making Ensures the Best Solutions Win",
    metaDescription:
      "When you think together honestly, the quality of a vision matters more than its source. Learn how anonymous decision making removes hierarchy and bias, enabling genuine collective wisdom in communities, organizations, and democratic processes.",
    date: "2026-03-27",
    author: "Joel Castro",
    keywords: [
      "anonymous decision making tool",
      "civic decision making process",
      "anonymous voting platform",
      "bias-free democratic decisions",
      "participatory democracy tool",
      "collective intelligence",
      "community consensus building",
    ],
    sections: [
      { type: "heading", text: "The Hidden Cost of Knowing Who Said What" },
      {
        type: "paragraph",
        text: "Picture a typical team meeting. The VP shares an idea. A few people nod. A junior developer has a better approach but stays quiet because contradicting the VP feels risky. Someone else builds on the VP’s idea — not because it’s the strongest, but because agreeing with leadership is the path of least resistance.",
      },
      {
        type: "paragraph",
        text: "The meeting ends. A decision gets made. And the best idea in the room never got heard.",
      },
      {
        type: "paragraph",
        text: "This isn’t a failure of talent or intention. It’s a structural problem: when people know who proposed an idea, they can’t help but evaluate the person alongside the idea. Decades of organizational research confirm what most of us already feel — hierarchy, confidence, and social dynamics shape group outcomes more than the actual quality of the proposals on the table.",
      },
      {
        type: "paragraph",
        text: "Anonymous decision making fixes this by design. And in this article, we’ll explore exactly why removing names from the process leads to better group decisions — along with practical approaches you can use starting today.",
      },
      { type: "divider" },

      { type: "heading", text: "Why Names Poison Group Decisions" },
      {
        type: "paragraph",
        text: "Before we talk solutions, it’s worth understanding the specific biases that creep in when ideas are attached to identities. These aren’t character flaws — they’re well-documented cognitive patterns that affect everyone.",
      },
      { type: "subheading", text: "Authority bias" },
      {
        type: "paragraph",
        text: "When a manager or senior team member proposes something, the group tends to defer. Not because the idea is best, but because disagreeing with authority carries social cost. Studies show that teams are significantly more likely to adopt a proposal from a high-status member — regardless of objective quality.",
      },
      { type: "subheading", text: "Anchoring" },
      {
        type: "paragraph",
        text: "The first idea shared in a discussion sets an anchor. Subsequent proposals get evaluated relative to it, not on their own merits. If the CEO speaks first (and they usually do), every other idea is unconsciously measured against that anchor.",
      },
      { type: "subheading", text: "Conformity pressure" },
      {
        type: "paragraph",
        text: "Solomon Asch’s conformity experiments showed that people will give obviously wrong answers just to match the group. In professional settings, this manifests as quiet agreement — nodding along in meetings, not raising objections, “going with the flow.” The result is decisions that seem like consensus but are actually just compliance.",
      },
      { type: "subheading", text: "The loudness problem" },
      {
        type: "paragraph",
        text: "Research consistently shows that the person who talks the most in a meeting has disproportionate influence on the outcome — even when their contributions aren’t the highest quality. Extroverts and confident speakers dominate group discussions not because they have better ideas, but because the process rewards volume over substance.",
      },
      {
        type: "paragraph",
        text: "These biases don’t disappear with good intentions. The only reliable solution is structural: remove the information that triggers the bias in the first place.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "How Anonymous Decision Making Changes the Equation",
      },
      {
        type: "paragraph",
        text: "An anonymous decision making tool for teams doesn’t just hide names — it fundamentally restructures how ideas compete.",
      },
      { type: "subheading", text: "Ideas stand on their own merit" },
      {
        type: "paragraph",
        text: "When nobody knows who proposed “restructure the Q3 timeline” versus “add a two-week buffer,” each idea gets evaluated purely on its substance. The intern’s idea competes on equal footing with the director’s.",
      },
      { type: "subheading", text: "Quiet voices get heard" },
      {
        type: "paragraph",
        text: "In a typical meeting, introverts, new team members, and people from underrepresented groups are statistically less likely to speak up. Anonymous group decisions eliminate the social risk of proposing something. You don’t need confidence to share an idea — you just need the idea itself.",
      },
      { type: "subheading", text: "Honesty increases" },
      {
        type: "paragraph",
        text: "When there’s no social penalty for disagreeing with the popular option, people rate proposals based on what they actually think — not what they think they should say.",
      },
      { type: "subheading", text: "Better ideas surface" },
      {
        type: "paragraph",
        text: "When you remove bias from evaluation and lower the barrier to participation, the pool of ideas gets larger and the selection process gets fairer. Organizations that use anonymous ideation processes report higher team satisfaction with outcomes and stronger follow-through on decisions.",
      },
      { type: "divider" },

      { type: "heading", text: "Common Approaches to Anonymous Group Decisions" },
      {
        type: "paragraph",
        text: "Anonymous decision making isn’t new. Several established methods use anonymity in different ways. If you’re exploring group decision-making methods, here’s how the anonymous options compare:",
      },
      { type: "subheading", text: "Anonymous surveys" },
      {
        type: "paragraph",
        text: "The simplest approach. Send out a form and collect responses without names. Easy to set up and familiar to everyone. But it’s one-shot — you collect opinions but there’s no mechanism for ideas to evolve or compete.",
      },
      { type: "subheading", text: "The Delphi Method" },
      {
        type: "paragraph",
        text: "Developed by the RAND Corporation in the 1950s, the Delphi Method collects anonymous expert opinions across multiple rounds. It’s well-researched but designed for expert panels, not everyday teams. Takes days or weeks per cycle and requires a dedicated facilitator.",
      },
      { type: "subheading", text: "Anonymous voting tools" },
      {
        type: "paragraph",
        text: "Tools like Slido or Mentimeter let groups vote anonymously in real time. Fast and engaging — but they anonymize the voting, not the proposing. Someone still has to stand up and suggest the options. As we explored in Voting vs. Consensus, whoever frames the options controls the outcome.",
      },
      { type: "subheading", text: "Suggestion boxes" },
      {
        type: "paragraph",
        text: "The classic anonymous input method. Zero barrier to participation and truly anonymous — but no evaluation mechanism. Ideas go in but there’s no structured way for the group to rate, compare, or iterate on them.",
      },
      { type: "divider" },

      { type: "heading", text: "What’s Missing from These Approaches" },
      {
        type: "paragraph",
        text: "Notice a pattern? Most anonymous decision-making tools solve part of the problem but leave gaps:",
      },
      {
        type: "bullets",
        items: [
          "Anonymous surveys anonymize input but don’t help the group evaluate or converge.",
          "The Delphi Method adds rounds but requires heavy facilitation and isn’t practical for routine decisions.",
          "Anonymous voting tools anonymize evaluation but not proposal generation — so bias enters at the framing stage.",
          "Suggestion boxes anonymize proposals but have no evaluation process at all.",
        ],
      },
      {
        type: "paragraph",
        text: "The ideal anonymous decision making tool for teams would combine all three: anonymous proposing, head-to-head voting that ranks ideas on merit, and threads that branch so the group's best thinking rises to the top.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "Head-to-Head Voting: Anonymity That Actually Works",
      },
      {
        type: "paragraph",
        text: "This is the approach behind OneMind — a conversation that ranks itself, where everyone’s anonymous and the best ideas rise on merit.",
      },
      { type: "subheading", text: "Step 1: Everyone proposes anonymously" },
      {
        type: "paragraph",
        text: "The group receives a question or decision prompt. Every participant submits their proposed answer — with no names attached. There’s a time limit to keep things moving. A team of 8 might generate 8 different proposals in the time it would take to discuss 2 in a traditional meeting.",
      },
      { type: "subheading", text: "Step 2: Everyone votes head-to-head" },
      {
        type: "paragraph",
        text: "Instead of a binary vote, each participant is shown two ideas at a time and picks the stronger. Position comes from how often an idea wins these direct comparisons, judged by everyone—like Elo, not likes or upvotes. This captures nuance an up-or-down vote misses: an idea that quietly beats every rival often rises to the top.",
      },
      { type: "subheading", text: "Step 3: The best rise on merit" },
      {
        type: "paragraph",
        text: "Ideas sort themselves into a live, merit-ranked list. Anyone can reply to any idea, and that reply opens its own ranked thread—infinitely nested—so ideas keep proving themselves instead of being locked in by a single vote.",
      },
      { type: "subheading", text: "Step 4: The top of the ranking is your answer" },
      {
        type: "paragraph",
        text: "The idea that keeps winning its head-to-head matchups sits at the top—genuine group alignment on merit, not a forced compromise. The group’s answer is simply what the voting ranks highest.",
      },
      { type: "diagram" },
      { type: "divider" },

      { type: "heading", text: "Real-World Examples" },
      {
        type: "subheading",
        text: "Workplace: Choosing a new project management tool",
      },
      {
        type: "paragraph",
        text: "A 20-person engineering team needs to standardize on a project management tool. With anonymous proposing, all 20 engineers submit their recommendation without names and vote head-to-head. A tool the team lead hadn’t even considered rises to the top on merit—17 of 20 ranked it highly. Adoption is smooth because the process felt fair.",
      },
      {
        type: "subheading",
        text: "Committee: Allocating a community grant budget",
      },
      {
        type: "paragraph",
        text: "A nonprofit committee with board members, community reps, and staff needs to allocate $50,000 across competing programs. Anonymous proposals level the field. Head-to-head voting reveals the group agrees on 80% of the allocation — focusing discussion on the remaining 20%. Total time: 45 minutes instead of three contentious meetings.",
      },
      {
        type: "subheading",
        text: "Student organization: Planning the annual event",
      },
      {
        type: "paragraph",
        text: "A university student government plans its flagship event. Anonymous submission generates proposals from every member — including creative formats newer members would never have pitched in an open meeting. A hybrid concept rises to the top on merit, winning the most head-to-head matchups.",
      },
      { type: "divider" },

      { type: "heading", text: "When Anonymity Isn’t the Right Call" },
      {
        type: "paragraph",
        text: "Intellectual honesty requires acknowledging that anonymous decision making isn’t universally superior:",
      },
      {
        type: "bullets",
        items: [
          "Accountability matters more than ideation — if you need to know who committed to what, anonymity defeats the purpose.",
          "The group is very small and trusts each other deeply.",
          "Expertise needs to be weighted — in some technical decisions, knowing the source is genuinely useful.",
          "Speed is the only priority — for trivial, reversible decisions, anonymous processes add unnecessary overhead.",
        ],
      },
      {
        type: "paragraph",
        text: "The key insight is matching the process to the stakes. High-stakes decisions where buy-in matters and power dynamics exist? That’s exactly where an anonymous decision making tool for teams earns its value.",
      },
      { type: "divider" },

      { type: "heading", text: "Making the Shift: Practical Tips" },
      { type: "subheading", text: "Start with a real decision, not a test" },
      {
        type: "paragraph",
        text: "Don’t pilot anonymous decision making on something trivial. Pick a decision that actually matters — one where you’ve experienced the dynamics described in this article.",
      },
      { type: "subheading", text: "Explain the why" },
      {
        type: "paragraph",
        text: "Be direct with your team: “We’re trying anonymous proposals because I want everyone’s ideas to compete on merit, not on who said them.” Most people respond well to that framing.",
      },
      { type: "subheading", text: "Commit to the outcome" },
      {
        type: "paragraph",
        text: "If the group converges on an answer and the manager vetoes it, you’ve destroyed trust in the process permanently. Before you start, decide whether you’ll genuinely honor the group’s outcome.",
      },
      { type: "divider" },

      { type: "heading", text: "Try Bias-Free Decision Making with OneMind" },
      {
        type: "paragraph",
        text: "OneMind is a free app where a conversation ranks itself. Everyone's anonymous—groups submit ideas, vote on them head-to-head, and the best rise to the top on merit, not by who said them or how loud they were.",
      },
      {
        type: "paragraph",
        text: "No accounts required. No downloads. Works on any device with a browser. Your team can run its first anonymous decision in under five minutes.",
      },
      {
        type: "cta",
        text: "If you’ve ever left a meeting thinking “we didn’t pick the best idea — we just picked the loudest one,” OneMind is built for you.",
        buttonLabel: "Try OneMind Free",
        route: "/tutorial",
      },
    ],
  },

  // -------------------------------------------------------------------------
  // Post 2: Voting vs. Consensus (_votingVsConsensus)
  // -------------------------------------------------------------------------
  {
    slug: "voting-vs-consensus",
    title:
      "Refine Each Other's Ideas: Democratic Decision-Making Beyond Voting and Consensus",
    metaDescription:
      "Voting creates winners and losers. Traditional consensus takes forever. Discover a third way: an anonymous conversation that ranks itself by head-to-head voting, so the best ideas win on merit.",
    date: "2026-03-24",
    author: "Joel Castro",
    keywords: [
      "voting vs consensus",
      "democratic decision making",
      "consensus building",
      "participatory democracy",
      "civic decision making",
      "community consensus",
      "alternatives to majority voting",
    ],
    sections: [
      {
        type: "paragraph",
        text: "Your team has a decision to make. Someone suggests, “Let’s just vote on it.”",
      },
      {
        type: "paragraph",
        text: "It sounds democratic. It sounds fast. But voting is often where alignment goes to die.",
      },
      {
        type: "paragraph",
        text: "Here’s why — and what actually works instead.",
      },
      { type: "divider" },

      { type: "heading", text: "The Problem with Voting" },
      {
        type: "paragraph",
        text: "Voting feels fair. Everyone gets a say, majority rules. But in practice, voting has three critical flaws:",
      },
      { type: "subheading", text: "It creates losers" },
      {
        type: "paragraph",
        text: "If the vote is 6-4, those four people didn’t just lose a preference — they lost influence. They walk away feeling unheard. Over time, this breeds quiet disengagement or outright resentment.",
      },
      { type: "subheading", text: "It rewards framing, not ideas" },
      {
        type: "paragraph",
        text: "You can only vote on what’s presented. Whoever controls the options controls the outcome. This is why experienced politicians spend more energy framing the question than answering it.",
      },
      { type: "subheading", text: "It stops thinking too early" },
      {
        type: "paragraph",
        text: "Once you vote, the decision is “done.” There’s no mechanism for an initial minority position to prove itself stronger over time. The best idea might have lost because it was unfamiliar, not because it was wrong.",
      },
      { type: "divider" },

      { type: "heading", text: "The Problem with Traditional Consensus" },
      {
        type: "paragraph",
        text: "Frustrated by voting, some teams swing to the opposite extreme: “We won’t decide until everyone agrees.”",
      },
      {
        type: "paragraph",
        text: "This sounds noble but creates its own problems:",
      },
      { type: "subheading", text: "It takes forever" },
      {
        type: "paragraph",
        text: "One person’s hesitation can block the entire group. Discussions spiral as the team tries to accommodate every concern.",
      },
      { type: "subheading", text: "Silence gets mistaken for agreement" },
      {
        type: "paragraph",
        text: "When the facilitator asks “Does anyone object?”, social pressure kicks in. People stay quiet to avoid being the blocker — even when they have genuine concerns.",
      },
      { type: "subheading", text: "It produces watered-down compromises" },
      {
        type: "paragraph",
        text: "To get everyone on board, the decision gets edited until it’s the least objectionable option rather than the best one. Nobody hates it, but nobody loves it either.",
      },
      { type: "divider" },

      { type: "heading", text: "Why Teams Get Stuck" },
      {
        type: "paragraph",
        text: "The real problem isn’t voting OR consensus. It’s the assumption that these are the only two options.",
      },
      {
        type: "paragraph",
        text: "Most teams operate in a cycle: they try discussion-then-voting, get frustrated with the winners/losers dynamic, switch to consensus-seeking, get frustrated with how long it takes, and swing back to voting. Neither approach addresses the root cause.",
      },
      {
        type: "paragraph",
        text: "The root cause is this: in both models, WHO says something matters as much as WHAT they say. The manager’s suggestion carries more weight. The loudest voice gets more airtime. The first idea anchors the discussion. These are not personality problems — they’re structural problems baked into the process.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "The Third Option: A Conversation That Ranks Itself",
      },
      {
        type: "paragraph",
        text: "What if you could get the speed of voting with the alignment of consensus — without the downsides of either?",
      },
      {
        type: "paragraph",
        text: "That’s what a self-ranking conversation does. Here’s how it works:",
      },
      { type: "subheading", text: "Anonymous proposing" },
      {
        type: "paragraph",
        text: "Instead of discussing ideas out loud (where hierarchy and confidence bias the conversation), everyone submits ideas anonymously. This one structural change eliminates most of the dysfunction in group decision-making.",
      },
      { type: "subheading", text: "Head-to-head voting" },
      {
        type: "paragraph",
        text: "Instead of a binary vote, you’re shown two ideas at a time and pick the stronger. An idea’s position comes from how often it wins these direct comparisons, judged by everyone—like Elo, not likes or upvotes. This captures nuance up/down voting misses: an idea that quietly beats every rival can rise to the top.",
      },
      { type: "subheading", text: "Branching threads" },
      {
        type: "paragraph",
        text: "Unlike a one-shot vote, any idea can be replied to—and that reply opens its own ranked thread, infinitely nested. The conversation self-organizes into a living tree of ideas, and the ones that keep winning their matchups rise to the top on merit—genuine alignment, not forced agreement.",
      },
      {
        type: "paragraph",
        text: "This approach works because it separates idea quality from social dynamics. The best idea wins regardless of who proposed it, how confidently they speak, or where they sit in the org chart.",
      },
      { type: "diagram" },
      { type: "divider" },

      { type: "heading", text: "When to Use Which Approach" },
      {
        type: "paragraph",
        text: "Not every decision needs a self-ranking conversation. Here’s a practical guide:",
      },
      {
        type: "bullets",
        items: [
          "Use voting when the decision is low-stakes, reversible, or the group has no strong feelings. “What should we order for lunch?” doesn’t need a consensus process.",
          "Use traditional consensus when the group is small (3–5 people), trusts each other deeply, and has unlimited time. Co-founder decisions, for example, often work well with open consensus.",
          "Use anonymous head-to-head ranking when the decision matters, the group is larger than 5, there are power dynamics at play, or you need people to genuinely support the outcome — not just tolerate it.",
        ],
      },
      {
        type: "cta",
        text: "OneMind is a conversation that ranks itself — anonymous ideas, head-to-head voting, branching threads where the best rise on merit — right in your browser. No accounts, no downloads.",
        buttonLabel: "Try OneMind Free",
        route: "/tutorial",
      },
    ],
  },

  // -------------------------------------------------------------------------
  // Post 1: Group Decision Making Methods (_groupDecisionMakingMethods)
  // -------------------------------------------------------------------------
  {
    slug: "group-decision-making-methods",
    title:
      "5 Decision-Making Methods Where the Best Solutions Win—No Matter Who Proposes Them",
    metaDescription:
      "Compare 5 decision-making techniques for communities and organizations. Discover the approach that ensures quality matters more than hierarchy, where people from different backgrounds contribute to collective intelligence.",
    date: "2026-03-24",
    author: "Joel Castro",
    keywords: [
      "civic decision making methods",
      "community decision making techniques",
      "participatory democracy",
      "consensus building for communities",
      "group problem solving",
      "democratic governance tools",
      "collective decision making",
    ],
    sections: [
      {
        type: "paragraph",
        text: "Every team makes group decisions. Most do it badly.",
      },
      {
        type: "paragraph",
        text: "The default approach — whoever talks the most in the meeting wins — wastes time, frustrates quiet team members, and produces decisions nobody fully supports. But it doesn’t have to be this way.",
      },
      {
        type: "paragraph",
        text: "Here are five group decision-making methods, ranked from simplest to most effective, with honest trade-offs for each.",
      },
      { type: "divider" },

      { type: "heading", text: "1. Majority Voting" },
      { type: "subheading", text: "How it works" },
      {
        type: "paragraph",
        text: "Everyone votes. The option with more than 50% wins.",
      },
      { type: "subheading", text: "Best for" },
      {
        type: "paragraph",
        text: "Low-stakes decisions with clear binary options (“Do we move the meeting to Tuesday or Thursday?”).",
      },
      { type: "subheading", text: "The problem" },
      {
        type: "paragraph",
        text: "Voting creates winners and losers. The 49% who voted differently feel unheard. It also rewards whoever frames the options — you can only vote on what’s put in front of you. For important decisions, this breeds resentment, not alignment.",
      },
      { type: "divider" },

      { type: "heading", text: "2. Dot Voting (Multi-Voting)" },
      { type: "subheading", text: "How it works" },
      {
        type: "paragraph",
        text: "Each person gets a fixed number of “dots” (votes) to distribute across options. Options with the most dots rise to the top.",
      },
      { type: "subheading", text: "Best for" },
      {
        type: "paragraph",
        text: "Narrowing down a large list of ideas (e.g., brainstorming sessions, sprint planning).",
      },
      { type: "subheading", text: "The problem" },
      {
        type: "paragraph",
        text: "It’s still a popularity contest, just with more granularity. Anchoring bias is real — the first ideas presented or the ones from senior people tend to get more dots. And it still doesn’t tell you WHY people prefer something.",
      },
      { type: "divider" },

      { type: "heading", text: "3. Delphi Method" },
      { type: "subheading", text: "How it works" },
      {
        type: "paragraph",
        text: "Experts answer questions individually and anonymously across multiple rounds. After each round, results are shared and experts revise their answers. Over rounds, opinions converge.",
      },
      { type: "subheading", text: "Best for" },
      {
        type: "paragraph",
        text: "Complex forecasting or technical decisions where expertise matters more than politics.",
      },
      { type: "subheading", text: "The problem" },
      {
        type: "paragraph",
        text: "It’s slow (days to weeks), requires a dedicated facilitator, and works best with domain experts — not everyday team decisions. Most teams don’t have the patience or structure to run it.",
      },
      { type: "divider" },

      { type: "heading", text: "4. Consent-Based Decision Making (Sociocracy)" },
      { type: "subheading", text: "How it works" },
      {
        type: "paragraph",
        text: "Instead of asking “Does everyone agree?”, you ask “Does anyone have a principled objection?” If no one objects, the decision passes.",
      },
      { type: "subheading", text: "Best for" },
      {
        type: "paragraph",
        text: "Organizations that want to move fast while respecting dissent. Common in co-ops, non-profits, and agile teams.",
      },
      { type: "subheading", text: "The problem" },
      {
        type: "paragraph",
        text: "“No objection” isn’t the same as genuine support. People stay silent for many reasons — social pressure, fatigue, not wanting to be “that person.” You can end up with decisions that nobody actively opposes but nobody truly believes in either.",
      },
      { type: "divider" },

      {
        type: "heading",
        text: "5. Anonymous Head-to-Head Ranking (A Conversation That Ranks Itself)",
      },
      { type: "subheading", text: "How it works" },
      {
        type: "paragraph",
        text: "Everyone proposes ideas anonymously. The group votes head-to-head—shown two ideas at a time, pick the stronger—and each idea’s position comes from how often it wins these direct comparisons, like Elo. The best rise to the top on merit, and any idea can be replied to, opening its own ranked thread. The idea at the top is the group’s genuine answer.",
      },
      { type: "subheading", text: "Best for" },
      {
        type: "paragraph",
        text: "Any decision where you need real buy-in, not just compliance. Works for remote teams, large groups, and politically sensitive topics.",
      },
      { type: "subheading", text: "Why it works" },
      {
        type: "paragraph",
        text: "Anonymous proposals remove bias — ideas are judged on merit, not who said them. Head-to-head voting forces the group to genuinely compare rather than just react, and branching threads let strong ideas deepen instead of being locked in by a single vote. Because the process is transparent and fair, people trust the outcome even when their idea didn’t win.",
      },
      {
        type: "paragraph",
        text: "This is the approach that OneMind is built on.",
      },
      { type: "diagram" },
      {
        type: "cta",
        text: "Try a self-ranking conversation with your team — free, no account needed.",
        buttonLabel: "Try OneMind Free",
        route: "/tutorial",
      },
      { type: "divider" },

      { type: "heading", text: "Which Method Should You Use?" },
      { type: "paragraph", text: "Quick rule of thumb:" },
      {
        type: "bullets",
        items: [
          "Binary, low-stakes? → Majority vote",
          "Narrowing a long list? → Dot voting",
          "Expert forecasting? → Delphi method",
          "Need to move fast with no blockers? → Consent-based",
          "Need genuine alignment on important decisions? → Anonymous head-to-head ranking",
        ],
      },
      {
        type: "paragraph",
        text: "The key insight is that most teams default to discussion + voting for EVERYTHING, when it’s actually the worst fit for their most important decisions. The more a decision matters, the more structure you need in the process.",
      },
      {
        type: "cta",
        text: "Ready to see a conversation rank itself? OneMind runs the whole thing — anonymous ideas, head-to-head voting, branching threads where the best rise on merit — in your browser.",
        buttonLabel: "Start for Free",
        route: "/tutorial",
      },
    ],
  },
];

export function getPost(slug: string): BlogPost | null {
  return blogPosts.find((p) => p.slug === slug) ?? null;
}
