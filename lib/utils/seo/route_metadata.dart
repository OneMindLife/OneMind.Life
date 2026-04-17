/// Route-to-metadata mapping for SEO.
class RouteMetadata {
  final String title;
  final String description;
  final String canonicalPath;
  final bool noindex;

  const RouteMetadata({
    required this.title,
    required this.description,
    required this.canonicalPath,
    this.noindex = false,
  });
}

const _baseUrl = 'https://onemind.life';

const _defaultMetadata = RouteMetadata(
  title: 'OneMind – Group Consensus & Decision Making Software',
  description:
      'OneMind helps teams reach real consensus through anonymous proposing and '
      'transparent rating. No politics, no meetings required. A free facilitation '
      'tool for group decision making and team alignment.',
  canonicalPath: '/',
);

const _metadataMap = <String, RouteMetadata>{
  '/': _defaultMetadata,
  '/tutorial': RouteMetadata(
    title: 'How It Works | OneMind',
    description:
        'See how OneMind builds trust through fair, transparent consensus. '
        'Propose ideas, rate openly, and reach outcomes no one can manipulate.',
    canonicalPath: '/tutorial',
  ),
  '/demo': RouteMetadata(
    title: 'Demo – Trusted Consensus in Action | OneMind',
    description:
        'Watch real groups reach trusted decisions — no hidden algorithms, '
        'no gatekeepers. See transparent consensus in action.',
    canonicalPath: '/demo',
  ),
  '/privacy': RouteMetadata(
    title: 'Privacy Policy | OneMind',
    description: 'OneMind privacy policy — how we collect, use, and '
        'protect your data.',
    canonicalPath: '/privacy',
  ),
  '/terms': RouteMetadata(
    title: 'Terms of Service | OneMind',
    description: 'OneMind terms of service — rules and guidelines for '
        'using the platform.',
    canonicalPath: '/terms',
  ),
  '/home-tour': RouteMetadata(
    title: 'Take the Tour | OneMind',
    description:
        'Explore how OneMind helps groups reach transparent, trusted decisions. '
        'See the platform in action.',
    canonicalPath: '/home-tour',
  ),
  '/discover': RouteMetadata(
    title: 'Discover | OneMind',
    description:
        'Find consensus-powered groups and join decisions that matter. '
        'Discover how communities build trust with OneMind.',
    canonicalPath: '/discover',
  ),
  '/blog': RouteMetadata(
    title: 'Blog | OneMind',
    description:
        'Insights on group decision making, consensus building, and team '
        'alignment. Learn techniques to make better decisions together.',
    canonicalPath: '/blog',
  ),
  '/blog/voting-vs-consensus': RouteMetadata(
    title: 'Voting vs. Consensus: Why Your Team Gets Stuck | OneMind',
    description:
        'Voting creates winners and losers. Traditional consensus takes '
        'forever. Learn why both fail and discover structured convergence '
        '\u2014 a third approach that finds real alignment fast.',
    canonicalPath: '/blog/voting-vs-consensus',
  ),
  '/blog/group-decision-making-methods': RouteMetadata(
    title: '5 Group Decision-Making Methods That Actually Work | OneMind',
    description:
        'Compare 5 proven group decision-making techniques — from majority '
        'voting to structured consensus. Learn which method fits your team.',
    canonicalPath: '/blog/group-decision-making-methods',
  ),
  '/join': RouteMetadata(
    title: 'Join | OneMind',
    description: 'Join OneMind to participate in transparent group decisions.',
    canonicalPath: '/join',
    noindex: true,
  ),
  '/decision-making-tool': RouteMetadata(
    title: 'Group Decision Making Tool | OneMind',
    description:
        'OneMind is a group decision making tool that uses anonymous proposals '
        'and transparent rating to help teams make decisions they trust. '
        'Free, no account needed.',
    canonicalPath: '/decision-making-tool',
  ),
  '/consensus-building': RouteMetadata(
    title: 'Consensus Building Tool | OneMind',
    description:
        'Build real group consensus with OneMind. Structured rounds drive '
        'convergence — not compromise. Anonymous, fair, and transparent '
        'consensus building for any group.',
    canonicalPath: '/consensus-building',
  ),
  '/facilitation-tool': RouteMetadata(
    title: 'Online Facilitation Tool | OneMind',
    description:
        'OneMind is a facilitation tool that automates equal participation, '
        'fair evaluation, and transparent outcomes. Run structured group '
        'processes without a dedicated facilitator.',
    canonicalPath: '/facilitation-tool',
  ),
  '/loomio-alternative': RouteMetadata(
    title: 'Loomio Alternative | OneMind',
    description:
        'Looking for a Loomio alternative? OneMind replaces threaded discussions '
        'with structured rounds that drive real convergence. Anonymous, fast, '
        'and genuinely fair.',
    canonicalPath: '/loomio-alternative',
  ),
};

/// Returns metadata for the given [path], falling back to homepage defaults.
RouteMetadata getMetadataForPath(String path) {
  // Check for exact match first
  if (_metadataMap.containsKey(path)) {
    return _metadataMap[path]!;
  }
  
  // Check for /blog/* routes
  if (path.startsWith('/blog/')) {
    return RouteMetadata(
      title: 'Blog | OneMind',
      description:
          'Insights on group decision making, consensus building, '
          'and team alignment.',
      canonicalPath: path,
    );
  }
  
  // Check for /join/* wildcard routes (auth routes should be noindexed)
  if (path.startsWith('/join/')) {
    return const RouteMetadata(
      title: 'Join | OneMind',
      description: 'Join OneMind to participate in transparent group decisions.',
      canonicalPath: '/join',
      noindex: true,
    );
  }
  
  return _defaultMetadata;
}

/// Returns the full canonical URL for a path.
String canonicalUrl(String path) => '$_baseUrl$path';
