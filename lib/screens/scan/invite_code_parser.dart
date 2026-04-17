/// Extracts a 6-character invite code from a URL or bare code string.
/// Returns null if the input doesn't match.
String? extractInviteCode(String raw) {
  // Try URL pattern: .../join/ABCDEF
  final urlMatch = RegExp(r'/join/([A-Za-z0-9]{6})(?:[/?#]|$)').firstMatch(raw);
  if (urlMatch != null) return urlMatch.group(1)!.toUpperCase();

  // Try bare 6-char alphanumeric code
  final bare = raw.trim();
  if (RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(bare)) return bare.toUpperCase();

  return null;
}
