/// Keeps one SSE subscription to the server alive (PRD §8.1).
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

  Uri? _base;
  http.Client? _client;
  StreamSubscription<SseEvent>? _sub;
  Timer? _retryTimer;
  Timer? _watchdog;
  Duration _backoff = const Duration(seconds: 1);
  int _generation = 0;

  Link _link = Link.disconnected;
  bool _everConnected = false;
  String? _lastError;

  Uri? get base => _base;
  Link get link => _link;

  /// Whether a state has been received since [connect] was last called with
  /// a new address.
  bool get everConnected => _everConnected;

  /// Set when the last attempt failed; cleared on success.
  String? get lastError => _lastError;

  Stream<ReminderEvent> get reminders => _reminders.stream;

  /// Starts (or restarts) the subscription to [base].
  void connect(Uri base) {
    if (_base != base) {
      _everConnected = false;
      countdown.reset();
    }
    _base = base;
    _backoff = const Duration(seconds: 1);
    _restart();
  }

  /// Drops the current stream and connects again right away, e.g. after
  /// the PC wakes from sleep.
  void reconnect() {
    if (_base != null) _restart();
  }

  void disconnect() {
    _base = null;
    _stop();
    _everConnected = false;
    countdown.reset();
    _setLink(Link.disconnected);
  }

  void _stop() {
    _generation++;
    _retryTimer?.cancel();
    _watchdog?.cancel();
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  void _setLink(Link l) {
    if (_link == l) return;
    _link = l;
    notifyListeners();
  }

  void _restart() {
    _stop();
    final gen = _generation;
    final base = _base!;
    _setLink(Link.connecting);
    _open(base, gen);
  }

  Future<void> _open(Uri base, int gen) async {
    final client = _newClient();
    _client = client;
    try {
      final req = http.Request('GET', streamUri(base))
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final resp = await client.send(req).timeout(_connectTimeout);
      if (gen != _generation) return;
      final type = resp.headers['content-type'] ?? '';
      if (resp.statusCode != 200 || !type.startsWith('text/event-stream')) {
        throw StateError('HTTP ${resp.statusCode}');
      }
      _backoff = const Duration(seconds: 1);
      _lastError = null;
      _measureLatency(base, gen);
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
      }
    } on FormatException {
      // Ignore a malformed event rather than dropping the stream.
    }
  }

  void _fail(int gen, Object error) {
    if (gen != _generation || _base == null) return;
    _stop();
    _lastError = error.toString();
    _setLink(_everConnected ? Link.connecting : Link.disconnected);
    notifyListeners();
    final delay = _backoff;
    _backoff = _backoff * 2 > _maxBackoff ? _maxBackoff : _backoff * 2;
    final next = _generation;
    _retryTimer = Timer(delay, () {
      if (next == _generation && _base != null) _restart();
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
