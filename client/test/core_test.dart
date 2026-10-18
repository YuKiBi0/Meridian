import 'package:flutter_test/flutter_test.dart';
import 'package:meridian/core/address.dart';
import 'package:meridian/core/countdown.dart';
import 'package:meridian/core/display.dart';
import 'package:meridian/core/format.dart';
import 'package:meridian/core/protocol.dart';
import 'package:meridian/core/sse.dart';

TimerState state(int seq, TimerStatus status,
        {int total = 600000, int remaining = 600000, OnExpire onExpire = OnExpire.stop, String? runId = 'r1', String? lastEnd}) =>
    TimerState(
      seq: seq,
      runId: status == TimerStatus.idle ? null : runId,
      status: status,
      title: 'T',
      totalMs: total,
      remainingMs: remaining,
      overtimeMs: 0,
      onExpire: onExpire,
      marksMs: const [300000],
      serverTime: 0,
      lastEndRunId: lastEnd,
    );

void main() {
  group('format', () {
    test('remaining rounds up', () {
      expect(formatRemaining(0), '00:00');
      expect(formatRemaining(400), '00:01');
      expect(formatRemaining(299001), '05:00');
      expect(formatRemaining(3909000), '1:05:09');
      expect(formatOvertime(83900), '+01:23');
    });
    test('alert threshold', () {
      expect(alertThresholdMs(900000), 60000);
      expect(alertThresholdMs(60000), 12000);
    });
  });

  group('address', () {
    test('normalizes', () {
      expect(normalizeAddress('example.com/meridian/').toString(),
          'https://example.com/meridian');
      expect(normalizeAddress('https://x.com/meridian/api/v1/stream?role=client').toString(), 'https://x.com/meridian');
      expect(normalizeAddress('http://10.0.0.2:8090').toString(), 'http://10.0.0.2:8090');
      expect(normalizeAddress(''), isNull);
      expect(normalizeAddress('ftp://x'), isNull);
    });
    test('builds stream uri', () {
      expect(streamUri(normalizeAddress('x.com/meridian')!).toString(),
          'https://x.com/meridian/api/v1/stream?role=client');
      expect(timeUri(normalizeAddress('x.com')!).toString(), 'https://x.com/api/v1/time');
    });
  });

  test('sse decoder', () async {
    const raw = 'retry: 2000\n\nid: 3\nevent: state\ndata: {"a":1}\n\n: comment\nevent: sync\ndata: x\ndata: y\n\n';
    final events = await Stream<List<int>>.fromIterable([raw.codeUnits.sublist(0, 20), raw.codeUnits.sublist(20)])
        .transform(const SseDecoder())
        .toList();
    expect(events.map((e) => e.event), ['message', 'state', 'sync']);
    expect(events[0].retry, 2000);
    expect(events[1].id, '3');
    expect(events[2].data, 'x\ny');
  });

  group('countdown', () {
    late int clock;
    late Countdown c;
    setUp(() {
      clock = 0;
      c = Countdown(clock: () => clock);
    });

    test('extrapolates and expires locally', () {
      c.accept(state(1, TimerStatus.running, total: 60000, remaining: 60000));
      clock = 10000;
      expect(c.remainingMs, 50000);
      expect(c.inAlert, isFalse);
      clock = 49000;
      expect(c.inAlert, isTrue);
      clock = 61000;
      expect(c.expired, isTrue);
      expect(c.progress, 0);
    });

    test('drops stale states and applies latency', () {
      c.latencyMs = 50;
      c.accept(state(5, TimerStatus.running));
      expect(c.remainingMs, 600000 - 50);
      expect(c.accept(state(4, TimerStatus.paused)), isFalse);
      c.latencyMs = 100;
      expect(c.remainingMs, 600000 - 100);
    });

    test('sync corrects drift beyond 100ms only', () {
      c.accept(state(1, TimerStatus.running));
      clock = 1000;
      c.sync(const SyncEvent(seq: 1, status: TimerStatus.running, remainingMs: 598950, overtimeMs: 0));
      expect(c.remainingMs, 599000);
      c.sync(const SyncEvent(seq: 1, status: TimerStatus.running, remainingMs: 598500, overtimeMs: 0));
      expect(c.remainingMs, 598500);
    });

    test('overtime counts up', () {
      c.accept(state(1, TimerStatus.running, total: 10000, remaining: 1000, onExpire: OnExpire.overtime));
      clock = 3500;
      expect(c.overtimeMs, 2500);
      final d = DisplayModel.from(c, Link.connected, everConnected: true);
      expect(d.digits, '+00:02');
      expect(d.label, StatusLabel.timesUp);
    });

    test('ended shows for five seconds', () {
      c.accept(state(1, TimerStatus.running));
      c.accept(state(2, TimerStatus.idle, lastEnd: 'r1'));
      expect(DisplayModel.from(c, Link.connected, everConnected: true).label, StatusLabel.ended);
      clock = 5001;
      expect(DisplayModel.from(c, Link.connected, everConnected: true).label, StatusLabel.notStarted);
    });

    test('next change is the sooner of second and pixel', () {
      c.accept(state(1, TimerStatus.running, total: 600000, remaining: 300400));
      expect(c.nextChangeInMs(0), 400);
      expect(c.nextChangeInMs(6000), 100);
      c.accept(state(2, TimerStatus.paused, remaining: 1000));
      expect(c.nextChangeInMs(100), isNull);
    });

    test('display before any state waits for signal', () {
      final d = DisplayModel.from(c, Link.connecting, everConnected: false);
      expect(d.label, StatusLabel.waiting);
      expect(d.digits, '--:--');
    });
  });

  test('countdown uses a monotonic stopwatch by default', () async {
    final c = Countdown();
    c.accept(state(1, TimerStatus.running, remaining: 10000));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.remainingMs, lessThan(10000));
  });
}
