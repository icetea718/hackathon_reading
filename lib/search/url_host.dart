/// Host of [url] without a leading `www.`; empty when [url] is null/relative.
String hostOf(String? url) {
  if (url == null || url.isEmpty) return '';
  final host = Uri.tryParse(url)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}
