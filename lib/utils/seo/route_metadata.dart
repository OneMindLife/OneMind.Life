/// Route-to-metadata mapping for SEO.
class RouteMetadata {
  final String title;
  final String description;
  final String canonicalPath;

  const RouteMetadata({
    required this.title,
    required this.description,
    required this.canonicalPath,
  });
}

const _baseUrl = 'https://onemind.life';

const _defaultMetadata = RouteMetadata(
  title: 'OneMind – Decisions You Can Trust',
  description:
      'Transparent, crowdsourced consensus — not algorithms, not editors. '
      'OneMind lets groups reach decisions everyone can trust.',
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
};

/// Returns metadata for the given [path], falling back to homepage defaults.
RouteMetadata getMetadataForPath(String path) {
  return _metadataMap[path] ?? _defaultMetadata;
}

/// Returns the full canonical URL for a path.
String canonicalUrl(String path) => '$_baseUrl$path';
