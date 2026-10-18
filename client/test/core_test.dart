import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meridian/core/address.dart';
import 'package:meridian/core/connection.dart';
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
    test('reads the room', () {
      const id = '0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f506';
      final a = RoomAddress.parse('x.com/meridian/?r=${id.toUpperCase()}')!;
      expect(a.base.toString(), 'https://x.com/meridian');
      expect(a.room, id);
      expect(a.display, 'https://x.com/meridian?r=$id');
      expect(RoomAddress.parse(a.display), a);
      expect(RoomAddress.parse('x.com/meridian'), isNull);
      expect(RoomAddress.parse('x.com/meridian?r=nope'), isNull);
      expect(roomIdOf('x.com/meridian?r=nope'), isNull);
      expect(normalizeAddress('x.com/meridian?r=nope').toString(), 'https://x.com/meridian');
    });
    test('builds uris', () {
      final a = RoomAddress.parse('x.com/meridian?r=0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f506')!;
      expect(streamUri(a).toString(),
          'https://x.com/meridian/api/v1/stream?role=client&r=0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f506');
      expect(roomUri(a).toString(), 'https://x.com/meridian/api/v1/rooms/0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f506');
      expect(timeUri(normalizeAddress('x.com')!).toString(), 'https://x.com/api/v1/time');
    });
  });

  group('room connection', () {
    final a = RoomAddress.parse('x.com/meridian?r=0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f506')!;
    const notFound = '{"error":{"code":"room_not_found","message":"房间不存在"}}';
    const idle = '{"seq":1,"status":"idle","title":"","total_ms":0,"remaining_ms":0}';

    /// A server whose stream sends [events] (raw SSE) and then stays open,
    /// or answers 404 room_not_found when [events] is null.
    ServerConnection serve(String? events, {String roomBody = '{"id":"x","name":"一号厅"}', int roomStatus = 200}) {
      return ServerConnection(Countdown(), clientFactory: () => MockClient.streaming((req, _) async {
            final path = req.url.path;
            if (path.endsWith('/time')) return http.StreamedResponse(Stream.value(utf8.encode('{"server_time":0}')), 200);
            if (path.contains('/rooms/')) return http.StreamedResponse(Stream.value(utf8.encode(roomBody)), roomStatus);
            if (events == null) return http.StreamedResponse(Stream.value(utf8.encode(notFound)), 404);
            final body = StreamController<List<int>>();
            body.add(utf8.encode(events));
            return http.StreamedResponse(body.stream, 200, headers: {'content-type': 'text/event-stream'});
          }));
    }

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('looks the room up', () async {
      expect(await serve('').lookUpRoom(a), '一号厅');
      expect(serve('', roomBody: notFound, roomStatus: 404).lookUpRoom(a), throwsA(isA<RoomNotFound>()));
      expect(serve('', roomBody: 'nginx', roomStatus: 404).lookUpRoom(a), throwsA(isNot(isA<RoomNotFound>())));
    });

    test('follows the room name', () async {
      final c = serve('event: room\ndata: {"id":"x","name":"二号厅"}\n\nevent: state\ndata: $idle\n\n');
      c.connect(a, roomName: '一号厅');
      expect(c.roomName, '一号厅');
      await settle();
      expect(c.roomName, '二号厅');
      expect(c.everConnected, isTrue);
      c.dispose();
    });

    test('stops when the room is deleted', () async {
      final c = serve('event: state\ndata: $idle\n\nevent: room_deleted\ndata: {"id":"x"}\n\n');
      c.connect(a);
      await settle();
      expect(c.roomGone, isTrue);
      expect(c.address, isNull);
      expect(c.link, Link.disconnected);
      c.dispose();
    });

    test('stops when the room is already gone', () async {
      final c = serve(null);
      c.connect(a);
      await settle();
      expect(c.roomGone, isTrue);
      c.dispose();
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
