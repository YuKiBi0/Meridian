/// Keeps one SSE subscription to a room alive (PRD §8.1).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'address.dart';
import 'countdown.dart';
import 'display.dart';
import 'protocol.dart';
import 'sse.dart';

/// Thrown by [ServerConnection.lookUpRoom] when the server has no such room.
class RoomNotFound implements Exception {
  const RoomNotFound();
}

class ServerConnection extends ChangeNotifier {
  ServerConnection(this.countdown, {http.Client Function()? clientFactory})
      : _newClient = clientFactory ?? http.Client.new;

  static const _connectTimeout = Duration(seconds: 10);
  // Three missed 15 s heartbeats.
  static const _silenceTimeout = Duration(seconds: 45);
  static const _maxBackoff = Duration(seconds: 30);

  final Countdown countdown;
  final http.Client Function() _newClient;
  final _reminders = StreamController<ReminderEvent>.broadcast();

  RoomAddress? _address;
  http.Client? _client;
  StreamSubscription<SseEvent>? _sub;
  Timer? _retryTimer;
  Timer? _watchdog;
  Duration _backoff = const Duration(seconds: 1);
  int _generation = 0;

  Link _link = Link.disconnected;
  bool _everConnected = false;
  String? _lastError;
  String? _roomName;
  bool _roomGone = false;

  RoomAddress? get address => _address;
  Link get link => _link;

  /// The room's name as last announced by the server.
  String? get roomName => _roomName;

  /// Set when the room was deleted; the connection has stopped for good.
  bool get roomGone => _roomGone;

  /// Whether a state has been received since [connect] was last called with
  /// a new address.
  bool get everConnected => _everConnected;

  /// Set when the last attempt failed; cleared on success.
  String? get lastError => _lastError;

  Stream<ReminderEvent> get reminders => _reminders.stream;

  /// Checks that the room exists before joining it (PRD CLI-01) and returns
  /// its name. Throws [RoomNotFound], or another error when the server
  /// cannot be reached.
  Future<String> lookUpRoom(RoomAddress a) async {
    final client = _newClient();
    try {
      final r = await client.get(roomUri(a)).timeout(_connectTimeout);
      // The server sends UTF-8; don't rely on a proxy keeping the charset.
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode == 404 && _isRoomNotFound(body)) throw const RoomNotFound();
      if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
      return ((jsonDecode(body) as Map<String, Object?>)['name'] as String?) ?? '';
    } finally {
      client.close();
    }
  }

  static bool _isRoomNotFound(String body) {
    try {
      final err = (jsonDecode(body) as Map<String, Object?>)['error'] as Map<String, Object?>?;
      return err?['code'] == 'room_not_found';
    } catch (_) {
      return false;
    }
  }

  /// Starts (or restarts) the subscription to the room at [a]. [roomName]
  /// is shown until the server announces the current one.
  void connect(RoomAddress a, {String? roomName}) {
    if (_address != a) {
      _everConnected = false;
      countdown.reset();
      _roomName = roomName;
    }
    _address = a;
    _roomGone = false;
    _backoff = const Duration(seconds: 1);
    _restart();
  }

  /// Drops the current stream and connects again right away, e.g. after
  /// the PC wakes from sleep.
  void reconnect() {
    if (_address != null) _restart();
  }

  void disconnect() {
    _address = null;
    _stop();
    _everConnected = false;
    countdown.reset();
    _setLink(Link.disconnected);
  }

  /// The room was deleted: stop for good and let the app ask for a new one.
  void _gone() {
    _address = null;
    _stop();
    _everConnected = false;
    _roomGone = true;
    countdown.reset();
    _link = Link.disconnected;
    notifyListeners();
  }

  void _stop() {
    _generation++;
    _retryTimer?.cancel();
    _watchdog?.cancel();
    final sub = _sub, client = _client;
    _sub = null;
    _client = null;
    // Close the socket only after the stream is cancelled, so the abort is
    // not reported as an error to a listener that no longer exists.
    if (sub != null) {
      unawaited(sub.cancel().whenComplete(() => client?.close()));
    } else {
      client?.close();
    }
  }

  void _setLink(Link l) {
    if (_link == l) return;
    _link = l;
    notifyListeners();
  }

  void _restart() {
    _stop();
    final gen = _generation;
    final a = _address!;
    _setLink(Link.connecting);
    _open(a, gen);
  }

  Future<void> _open(RoomAddress a, int gen) async {
    final client = _newClient();
    _client = client;
    try {
      final req = http.Request('GET', streamUri(a))
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final resp = await client.send(req).timeout(_connectTimeout);
      if (gen != _generation) return;
      // Deleted while we were away (or while the server was down).
      if (resp.statusCode == 404 && _isRoomNotFound(await resp.stream.bytesToString())) {
        if (gen == _generation) _gone();
        return;
      }
      final type = resp.headers['content-type'] ?? '';
      if (resp.statusCode != 200 || !type.startsWith('text/event-stream')) {
        throw StateError('HTTP ${resp.statusCode}');
      }
      _backoff = const Duration(seconds: 1);
      _lastError = null;
      _measureLatency(a.base, gen);
      _kick(gen);
      _sub = resp.stream.transform(const SseDecoder()).listen(
            (e) => _onEvent(e, gen),
            onError: (Object e) => _fail(gen, e),
            onDone: () => _fail(gen, 'closed'),
            cancelOnError: true,
          );
    } catch (e) {
      _fail(gen, e);
    }
  }

  void _kick(int gen) {
    _watchdog?.cancel();
    _watchdog = Timer(_silenceTimeout, () => _fail(gen, 'silent'));
  }

  void _onEvent(SseEvent e, int gen) {
    if (gen != _generation) return;
    _kick(gen);
    try {
      switch (e.event) {
        case 'state':
          final s = TimerState.fromJson(jsonDecode(e.data) as Map<String, Object?>);
          countdown.accept(s);
          _everConnected = true;
          _link = Link.connected;
          notifyListeners();
        case 'sync':
          countdown.sync(SyncEvent.fromJson(jsonDecode(e.data) as Map<String, Object?>));
        case 'reminder':
          _reminders.add(ReminderEvent.fromJson(jsonDecode(e.data) as Map<String, Object?>));
        case 'room':
          final name = (jsonDecode(e.data) as Map<String, Object?>)['name'] as String?;
          if (name != null && name != _roomName) {
            _roomName = name;
            notifyListeners();
          }
        case 'room_deleted':
          _gone();
      }
    } on FormatException {
      // Ignore a malformed event rather than dropping the stream.
    }
  }

  void _fail(int gen, Object error) {
    if (gen != _generation || _address == null) return;
    _stop();
    _lastError = error.toString();
    _setLink(_everConnected ? Link.connecting : Link.disconnected);
    notifyListeners();
    final delay = _backoff;
    _backoff = _backoff * 2 > _maxBackoff ? _maxBackoff : _backoff * 2;
    final next = _generation;
    _retryTimer = Timer(delay, () {
      if (next == _generation && _address != null) _restart();
    });
  }

  /// PRD CLI-06: three round trips, half of the fastest is the one-way delay.
  Future<void> _measureLatency(Uri base, int gen) async {
    final client = _newClient();
    try {
      var best = 1 << 30;
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        final r = await client.get(timeUri(base)).timeout(const Duration(seconds: 5));
        sw.stop();
        if (r.statusCode == 200 && sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
      }
      if (gen == _generation && best < 1 << 30) countdown.latencyMs = best ~/ 2;
    } catch (_) {
      // Keep the previous estimate.
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _stop();
    _reminders.close();
    super.dispose();
  }
}
