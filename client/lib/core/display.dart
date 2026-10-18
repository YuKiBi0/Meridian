/// What a style draws, derived from the countdown and the connection
/// (DESIGN §5.7).
library;

import 'countdown.dart';
import 'format.dart';
import 'protocol.dart';

enum Tone { muted, live, alert }

enum StatusLabel { none, waiting, notStarted, paused, timesUp, ended }

enum Link { connected, connecting, disconnected }

class DisplayModel {
  const DisplayModel({
    required this.digits,
    required this.progress,
    required this.tone,
    required this.label,
    required this.title,
    required this.link,
    required this.marks,
  });

  final String digits;
  final double progress;
  final Tone tone;
  final StatusLabel label;
  final String title;
  final Link link;

  /// Reminder points as fractions of the total (for CLI-24).
  final List<double> marks;

  bool get hasRun => label != StatusLabel.waiting && label != StatusLabel.notStarted && label != StatusLabel.ended;

  /// [everConnected] distinguishes "waiting for signal" (never had a state)
  /// from a temporary drop, during which the countdown keeps running.
  factory DisplayModel.from(Countdown c, Link link, {required bool everConnected}) {
    final s = c.state;
    if (!everConnected) {
      return DisplayModel(
        digits: placeholderDigits,
        progress: 0,
        tone: Tone.muted,
        label: StatusLabel.waiting,
        title: '',
        link: link,
        marks: const [],
      );
    }
    if (s.status == TimerStatus.idle) {
      return DisplayModel(
        digits: placeholderDigits,
        progress: 0,
        tone: Tone.muted,
        label: c.recentlyEnded ? StatusLabel.ended : StatusLabel.notStarted,
        title: '',
        link: link,
        marks: const [],
      );
    }
    final marks = [
      if (s.totalMs > 0)
        for (final m in s.marksMs)
          if (m > 0) m / s.totalMs,
    ];
    if (c.expired) {
      return DisplayModel(
        digits: s.onExpire == OnExpire.overtime ? formatOvertime(c.overtimeMs) : formatRemaining(0),
        progress: 0,
        tone: Tone.alert,
        label: StatusLabel.timesUp,
        title: s.title,
        link: link,
        marks: marks,
      );
    }
    final paused = s.status == TimerStatus.paused;
    return DisplayModel(
      digits: formatRemaining(c.remainingMs),
      progress: c.progress,
      tone: paused ? Tone.muted : (c.inAlert ? Tone.alert : Tone.live),
      label: paused ? StatusLabel.paused : StatusLabel.none,
      title: s.title,
      link: link,
      marks: marks,
    );
  }
}
