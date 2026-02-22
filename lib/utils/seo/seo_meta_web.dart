import 'package:web/web.dart' as web;

import 'route_metadata.dart';

/// Updates `<head>` meta tags for the current route on web.
void updateMetaTags(String path) {
  final meta = getMetadataForPath(path);
  final url = canonicalUrl(meta.canonicalPath);

  // Title
  web.document.title = meta.title;

  // Standard meta tags
  _setMeta('description', meta.description);

  // Canonical link
  _setCanonical(url);

  // Open Graph
  _setMetaProperty('og:title', meta.title);
  _setMetaProperty('og:description', meta.description);
  _setMetaProperty('og:url', url);

  // Twitter card
  _setMeta('twitter:title', meta.title);
  _setMeta('twitter:description', meta.description);

  // Remove noindex if it was set by a previous 404 page
  _removeNoIndex();
}

/// Sets `<meta name="robots" content="noindex">` for 404 / unknown routes.
void setNoIndex() {
  var tag = web.document.querySelector('meta[name="robots"]');
  if (tag == null) {
    tag = web.document.createElement('meta') as web.HTMLMetaElement;
    (tag as web.HTMLMetaElement).name = 'robots';
    web.document.head!.appendChild(tag);
  }
  (tag as web.HTMLMetaElement).content = 'noindex';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _setMeta(String name, String content) {
  var tag = web.document.querySelector('meta[name="$name"]');
  if (tag == null) {
    tag = web.document.createElement('meta') as web.HTMLMetaElement;
    (tag as web.HTMLMetaElement).name = name;
    web.document.head!.appendChild(tag);
  }
  (tag as web.HTMLMetaElement).content = content;
}

void _setMetaProperty(String property, String content) {
  var tag = web.document.querySelector('meta[property="$property"]');
  if (tag == null) {
    tag = web.document.createElement('meta') as web.HTMLMetaElement;
    tag.setAttribute('property', property);
    web.document.head!.appendChild(tag);
  }
  (tag as web.HTMLMetaElement).content = content;
}

void _setCanonical(String url) {
  var link = web.document.querySelector('link[rel="canonical"]');
  if (link == null) {
    link = web.document.createElement('link') as web.HTMLLinkElement;
    (link as web.HTMLLinkElement).rel = 'canonical';
    web.document.head!.appendChild(link);
  }
  (link as web.HTMLLinkElement).href = url;
}

void _removeNoIndex() {
  final tag = web.document.querySelector('meta[name="robots"]');
  tag?.remove();
}
