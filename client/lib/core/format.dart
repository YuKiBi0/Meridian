/// Time formatting shared by every style (DESIGN §5.4).
library;

String _pad(int n) => n.toString().padLeft(2, '0');

String _hms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${_pad(m)}:${_pad(s)}' : '${_pad(m)}:${_pad(s)}';
}

/// Remaining time, seconds rounded up so 00:00 appears exactly at zero.
String formatRemaining(int ms) => _hms(ms <= 0 ? 0 : (ms + 999) ~/ 1000);

/// Overtime as +MM:SS, seconds rounded down.
String formatOvertime(int ms) => '+${_hms(ms <= 0 ? 0 : ms ~/ 1000)}';

/// Placeholder shown when there is nothing to count.
const placeholderDigits = '--:--';

/// Remaining time below which the countdown turns vermilion (DESIGN §5.2).
int alertThresholdMs(int totalMs) => totalMs * 0.2 < 60000 ? (totalMs * 0.2).round() : 60000;
