/// Normalizes what the user typed as the server address (PRD CLI-02).
library;

const streamPath = '/api/v1/stream';

/// Returns the base address (scheme, host, path without trailing slash and
/// without /api/v1/stream), or null if [input] cannot be a server address.
Uri? normalizeAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    return null;
  }
  var path = uri.path;
  final at = path.indexOf(streamPath);
  if (at >= 0) path = path.substring(0, at);
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path);
}

Uri streamUri(Uri base) =>
    base.replace(path: '${base.path}$streamPath', queryParameters: {'role': 'client'});

Uri timeUri(Uri base) => base.replace(path: '${base.path}/api/v1/time');

/// The address as shown back to the user.
String displayAddress(Uri base) => base.toString();
