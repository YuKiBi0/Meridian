/// Normalizes what the user typed as the room address (PRD CLI-02):
/// the server address followed by `?r=<room id>`.
library;

const streamPath = '/api/v1/stream';

/// Returns the base address (scheme, host, path without trailing slash and
/// without /api/v1/stream), or null if [input] cannot be a server address.
/// Any query, including the room, is dropped.
Uri? normalizeAddress(String input) {
  final uri = _parse(input);
  if (uri == null) return null;
  var path = uri.path;
  final at = path.indexOf(streamPath);
  if (at >= 0) path = path.substring(0, at);
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path);
}

Uri? _parse(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    return null;
  }
  return uri;
}

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// Returns the room id from the ?r= of [input] in lowercase, or null when
/// there is none or it is not a UUID.
String? roomIdOf(String input) {
  final r = _parse(input)?.queryParameters['r']?.trim().toLowerCase();
  return r != null && _uuid.hasMatch(r) ? r : null;
}

/// A server and the room to join on it.
class RoomAddress {
  const RoomAddress(this.base, this.room);

  /// Parses [input], or returns null when the server address or the room is
  /// missing or malformed.
  static RoomAddress? parse(String input) {
    final base = normalizeAddress(input);
    final room = roomIdOf(input);
    return base == null || room == null ? null : RoomAddress(base, room);
  }

  final Uri base;

  /// Lowercase UUID.
  final String room;

  /// The address as shown back to the user and stored.
  String get display => base.replace(queryParameters: {'r': room}).toString();

  @override
  bool operator ==(Object other) => other is RoomAddress && other.base == base && other.room == room;

  @override
  int get hashCode => Object.hash(base, room);

  @override
  String toString() => display;
}

Uri streamUri(RoomAddress a) =>
    a.base.replace(path: '${a.base.path}$streamPath', queryParameters: {'role': 'client', 'r': a.room});

/// Public room lookup, used to check that the room exists before joining.
Uri roomUri(RoomAddress a) => a.base.replace(path: '${a.base.path}/api/v1/rooms/${a.room}');

Uri timeUri(Uri base) => base.replace(path: '${base.path}/api/v1/time');
