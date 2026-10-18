/// Local extrapolation of the server countdown (PRD §8.2).
///
/// The server sends the remaining time at the moment it sent the event; we
/// pin that to a monotonic clock reading and count from there. The system
/// wall clock is never used, so changing the PC's time has no effect.
library;

import 'format.dart';
import 'protocol.dart';

/// Milliseconds on a monotonic clock.
typedef MonotonicClock = int Function();

MonotonicClock stopwatchClock() {
  final sw = Stopwatch()..start();
  return () => sw.elapsedMilliseconds;
}

class Countdown {
  Countdown({MonotonicClock? clock}) : now = clock ?? stopwatchClock();

  static const endedVisibleMs = 5000;
  static const syncToleranceMs = 100;

  final MonotonicClock now;

  TimerState _state = TimerState.idle;
  int _anchorAt = 0;
  int? _endedAt;

  int _latencyMs = 0;

  /// One-way network delay subtracted from incoming remaining times.
  int get latencyMs => _latencyMs;

  /// Updates the delay estimate and shifts the current anchor to match.
  set latencyMs(int ms) {
    _anchorAt -= ms - _latencyMs;
    _latencyMs = ms;
  }

  TimerState get state => _state;

  /// Applies a state snapshot. Returns false if it was stale.
  bool accept(TimerState s) {
    if (s.seq < _state.seq) return false;
    final prev = _state;
    if (s.status == TimerStatus.idle &&
        prev.status != TimerStatus.idle &&
        s.lastEndRunId != null &&
        s.lastEndRunId == prev.runId) {
      _endedAt = now();
    } else if (s.status != TimerStatus.idle) {
      _endedAt = null;
    }
    _state = s;
    _anchorAt = now() - latencyMs;
    return true;
  }

  /// Applies a heartbeat; re-anchors when we drifted more than 100 ms.
  void sync(SyncEvent e) {
    if (e.seq != _state.seq) return;
    final drift = (remainingMs - e.remainingMs).abs() + (overtimeMs - e.overtimeMs).abs();
    if (drift > syncToleranceMs) {
      _state = _state.copyWith(remainingMs: e.remainingMs, overtimeMs: e.overtimeMs);
      _anchorAt = now() - latencyMs;
    }
  }

  /// Forgets everything, e.g. when switching servers.
  void reset() {
    _state = TimerState.idle;
    _endedAt = null;
  }

  int get _elapsed => now() - _anchorAt;

  int get remainingMs {
    if (_state.status != TimerStatus.running) return _state.remainingMs;
    final r = _state.remainingMs - _elapsed;
    return r > 0 ? r : 0;
  }

  /// True when the run has reached zero, on the server or locally.
  bool get expired =>
      _state.status == TimerStatus.expired ||
      (_state.status == TimerStatus.running && remainingMs <= 0);

  int get overtimeMs {
    if (_state.onExpire != OnExpire.overtime) return 0;
    if (_state.status == TimerStatus.expired) return _state.overtimeMs + _elapsed;
    if (_state.status == TimerStatus.running) {
      final over = _elapsed - _state.remainingMs;
      return over > 0 ? over : 0;
    }
    return 0;
  }

  bool get recentlyEnded {
    final at = _endedAt;
    return _state.status == TimerStatus.idle && at != null && now() - at < endedVisibleMs;
  }

  /// Progress 0..1 (share of total still remaining).
  double get progress {
    if (_state.status == TimerStatus.idle || _state.totalMs <= 0 || expired) return 0;
    return (remainingMs / _state.totalMs).clamp(0.0, 1.0);
  }

  bool get inAlert =>
      _state.status == TimerStatus.running &&
      (expired || remainingMs <= alertThresholdMs(_state.totalMs));

  /// How long until anything visible changes, given that progress is drawn
  /// across [pixelSpan] device pixels. Null when nothing will change on its
  /// own (PRD CLI-14: repaint only when needed).
  int? nextChangeInMs(double pixelSpan) {
    final s = _state;
    if (s.status == TimerStatus.running && !expired) {
      final rem = remainingMs;
      var next = rem % 1000 == 0 ? 1000 : rem % 1000;
      if (pixelSpan > 1 && s.totalMs > 0) {
        final msPerPixel = s.totalMs / pixelSpan;
        if (msPerPixel < next) next = msPerPixel.ceil();
      }
      final threshold = alertThresholdMs(s.totalMs);
      if (rem > threshold && rem - threshold < next) next = rem - threshold;
      return next.clamp(16, 1000);
    }
    if (expired && s.onExpire == OnExpire.overtime) {
      return (1000 - overtimeMs % 1000).clamp(16, 1000);
    }
    if (expired) return null;
    if (recentlyEnded) return endedVisibleMs - (now() - _endedAt!);
    return null;
  }
}
