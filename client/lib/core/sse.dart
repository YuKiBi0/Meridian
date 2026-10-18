/// A minimal server-sent events parser (enough for PRD §9.1).
library;

import 'dart:async';
import 'dart:convert';

class SseEvent {
  const SseEvent(this.event, this.data, {this.id, this.retry});

  final String event;
  final String data;
  final String? id;
  final int? retry;
}

/// Turns a UTF-8 byte stream into events.
class SseDecoder extends StreamTransformerBase<List<int>, SseEvent> {
  const SseDecoder();

  @override
  Stream<SseEvent> bind(Stream<List<int>> stream) async* {
    var event = '';
    final data = <String>[];
    String? id;
    int? retry;
    await for (final line in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty || retry != null) {
          yield SseEvent(event.isEmpty ? 'message' : event, data.join('\n'), id: id, retry: retry);
        }
        event = '';
        data.clear();
        retry = null;
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
        case 'data':
          data.add(value);
        case 'id':
          id = value;
        case 'retry':
          retry = int.tryParse(value);
      }
    }
  }
}
