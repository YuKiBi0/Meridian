/// Wire types mirroring PRD §9.1.
library;

enum TimerStatus { idle, running, paused, expired }

enum OnExpire { stop, overtime }

TimerStatus _status(Object? v) => TimerStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => TimerStatus.idle,
    );

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class TimerState {
  const TimerState({
    required this.seq,
    required this.runId,
    required this.status,
    required this.title,
    required this.totalMs,
    required this.remainingMs,
    required this.overtimeMs,
    required this.onExpire,
    required this.marksMs,
    required this.serverTime,
    this.lastEndRunId,
  });

  static const idle = TimerState(
    seq: -1,
    runId: null,
    status: TimerStatus.idle,
    title: '',
    totalMs: 0,
    remainingMs: 0,
    overtimeMs: 0,
    onExpire: OnExpire.stop,
    marksMs: [],
    serverTime: 0,
  );

  final int seq;
  final String? runId;
  final TimerStatus status;
  final String title;
  final int totalMs;
  final int remainingMs;
  final int overtimeMs;
  final OnExpire onExpire;
  final List<int> marksMs;
  final int serverTime;

  /// Set when the run was just ended by an operator.
  final String? lastEndRunId;

  factory TimerState.fromJson(Map<String, Object?> j) => TimerState(
        seq: _int(j['seq']),
        runId: j['run_id'] as String?,
        status: _status(j['status']),
        title: (j['title'] as String?) ?? '',
        totalMs: _int(j['total_ms']),
        remainingMs: _int(j['remaining_ms']),
        overtimeMs: _int(j['overtime_ms']),
        onExpire: j['on_expire'] == 'overtime' ? OnExpire.overtime : OnExpire.stop,
        marksMs: [for (final m in (j['marks_ms'] as List?) ?? const []) _int(m)],
        serverTime: _int(j['server_time']),
        lastEndRunId: (j['last_end'] as Map?)?['run_id'] as String?,
      );

  TimerState copyWith({int? remainingMs, int? overtimeMs}) => TimerState(
        seq: seq,
        runId: runId,
        status: status,
        title: title,
        totalMs: totalMs,
        remainingMs: remainingMs ?? this.remainingMs,
        overtimeMs: overtimeMs ?? this.overtimeMs,
        onExpire: onExpire,
        marksMs: marksMs,
        serverTime: serverTime,
        lastEndRunId: lastEndRunId,
      );
}

class SyncEvent {
  const SyncEvent({
    required this.seq,
    required this.status,
    required this.remainingMs,
    required this.overtimeMs,
  });

  final int seq;
  final TimerStatus status;
  final int remainingMs;
  final int overtimeMs;

  factory SyncEvent.fromJson(Map<String, Object?> j) => SyncEvent(
        seq: _int(j['seq']),
        status: _status(j['status']),
        remainingMs: _int(j['remaining_ms']),
        overtimeMs: _int(j['overtime_ms']),
      );
}

class ReminderEvent {
  const ReminderEvent({
    required this.runId,
    required this.reminderId,
    required this.atMs,
    required this.title,
    required this.text,
    required this.durationMs,
    required this.sticky,
  });

  final String runId;
  final String reminderId;
  final int atMs;
  final String title;
  final String text;
  final int durationMs;
  final bool sticky;

  factory ReminderEvent.fromJson(Map<String, Object?> j) => ReminderEvent(
        runId: (j['run_id'] as String?) ?? '',
        reminderId: (j['reminder_id'] as String?) ?? '',
        atMs: _int(j['at_ms']),
        title: (j['title'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        durationMs: _int(j['duration_ms']),
        sticky: j['sticky'] == true,
      );
}
