/// Pure window geometry: where the view and the reminder cards go for a
/// given work area and placement (PRD CLI-31, CLI-61). All rects are in
/// logical pixels of the target display.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../settings.dart';

const toastWidth = 320.0;
const toastCardHeight = 96.0;
const toastGap = 8.0;
const snapDistance = 24.0;

/// Which side of the view the reminder cards appear on.
enum ToastSide { below, above, right, left }

class Layout {
  const Layout({required this.window, required this.view, this.toast, this.toastSide = ToastSide.below});

  /// Window bounds on screen.
  final Rect window;

  /// View bounds relative to the window.
  final Rect view;

  /// Reminder area relative to the window, if any reminders are showing.
  final Rect? toast;
  final ToastSide toastSide;
}

Size toastAreaSize(int count) =>
    Size(toastWidth, count * toastCardHeight + (count - 1) * toastGap);

bool isFullLength(Placement p) =>
    p == Placement.top || p == Placement.bottom || p == Placement.left || p == Placement.right;

bool isVertical(Placement p) => p == Placement.left || p == Placement.right;

/// Places the view on screen.
Rect placeView(Rect work, Placement p, Size size, double m, {Offset? free}) {
  final w = size.width, h = size.height;
  final cx = work.center.dx - w / 2;
  final o = switch (p) {
    Placement.top || Placement.left || Placement.topLeft => Offset(work.left + m, work.top + m),
    Placement.bottom || Placement.bottomLeft => Offset(work.left + m, work.bottom - m - h),
    Placement.right || Placement.topRight => Offset(work.right - m - w, work.top + m),
    Placement.bottomRight => Offset(work.right - m - w, work.bottom - m - h),
    Placement.topCenter => Offset(cx, work.top + m),
    Placement.bottomCenter => Offset(cx, work.bottom - m - h),
    Placement.free => (free ?? Offset(work.right - m - w, work.top + m)),
  };
  return _clampInto(o & size, work);
}

Rect _clampInto(Rect r, Rect work) {
  final dx = r.width >= work.width ? work.left - r.left : (r.left < work.left ? work.left - r.left : (r.right > work.right ? work.right - r.right : 0.0));
  final dy = r.height >= work.height ? work.top - r.top : (r.top < work.top ? work.top - r.top : (r.bottom > work.bottom ? work.bottom - r.bottom : 0.0));
  return r.shift(Offset(dx, dy));
}

ToastSide toastSideFor(Placement p, Rect view, Rect work) => switch (p) {
      Placement.top || Placement.topLeft || Placement.topRight || Placement.topCenter => ToastSide.below,
      Placement.bottom || Placement.bottomLeft || Placement.bottomRight || Placement.bottomCenter => ToastSide.above,
      Placement.left => ToastSide.right,
      Placement.right => ToastSide.left,
      Placement.free => view.center.dy < work.center.dy ? ToastSide.below : ToastSide.above,
    };

/// Computes the full layout. [toasts] is the number of reminder cards and
/// [toastPosition] where they go.
Layout layoutFor({
  required Rect work,
  required Placement placement,
  required Size viewSize,
  required double margin,
  Offset? free,
  int toasts = 0,
  ToastPosition toastPosition = ToastPosition.followView,
}) {
  final view = placeView(work, placement, viewSize, margin, free: free);
  if (toasts <= 0) {
    return Layout(window: view, view: Offset.zero & view.size);
  }
  final ts = toastAreaSize(toasts);
  final (toast, side) = _cornerToast(work, view, ts, margin, toastPosition) ?? _followToast(work, view, ts, placement);
  final window = view.expandToInclude(toast);
  return Layout(
    window: window,
    view: view.shift(-window.topLeft),
    toast: toast.shift(-window.topLeft),
    toastSide: side,
  );
}

/// Cards right next to the view, on its inner side.
(Rect, ToastSide) _followToast(Rect work, Rect view, Size ts, Placement placement) {
  final side = toastSideFor(placement, view, work);
  final alignLeft = placement == Placement.topLeft ||
      placement == Placement.bottomLeft ||
      (placement == Placement.free && view.center.dx < work.center.dx);
  final alignRight = placement == Placement.topRight ||
      placement == Placement.bottomRight ||
      (placement == Placement.free && view.center.dx >= work.center.dx);
  double x() => alignLeft ? view.left : (alignRight ? view.right - ts.width : view.center.dx - ts.width / 2);
  final origin = switch (side) {
    ToastSide.below => Offset(x(), view.bottom + toastGap),
    ToastSide.above => Offset(x(), view.top - toastGap - ts.height),
    ToastSide.right => Offset(view.right + toastGap, view.center.dy - ts.height / 2),
    ToastSide.left => Offset(view.left - toastGap - ts.width, view.center.dy - ts.height / 2),
  };
  return (_clampInto(origin & ts, work), side);
}

/// Cards in a corner of the work area. When the view already sits there the
/// cards step past it (below/above first, then beside it); null when they
/// cannot fit, and the caller falls back to following the view.
(Rect, ToastSide)? _cornerToast(Rect work, Rect view, Size ts, double margin, ToastPosition pos) {
  if (pos == ToastPosition.followView) return null;
  final top = pos == ToastPosition.topRight || pos == ToastPosition.topLeft;
  final right = pos == ToastPosition.topRight || pos == ToastPosition.bottomRight;
  final inset = math.max(margin, toastGap);
  final x = right ? work.right - inset - ts.width : work.left + inset;
  final y = top ? work.top + inset : work.bottom - inset - ts.height;
  final side = top ? ToastSide.below : ToastSide.above;
  final candidates = [
    Offset(x, y) & ts,
    Offset(x, top ? view.bottom + toastGap : view.top - toastGap - ts.height) & ts,
    Offset(right ? view.left - toastGap - ts.width : view.right + toastGap, y) & ts,
  ];
  for (final r in candidates) {
    final inside = r.left >= work.left && r.top >= work.top && r.right <= work.right && r.bottom <= work.bottom;
    if (inside && !r.overlaps(view)) return (r, side);
  }
  return null;
}

/// After a free drag, returns the placement the view should snap to, or
/// [Placement.free] when it is not near any allowed anchor.
Placement snapPlacement(Rect view, Rect work, List<Placement> allowed, double margin) {
  bool near(double a, double b) => (a - b).abs() <= snapDistance;
  final left = near(view.left, work.left + margin);
  final right = near(view.right, work.right - margin);
  final top = near(view.top, work.top + margin);
  final bottom = near(view.bottom, work.bottom - margin);
  final center = near(view.center.dx, work.center.dx);
  final candidates = <Placement, bool>{
    Placement.topLeft: top && left,
    Placement.topRight: top && right,
    Placement.bottomLeft: bottom && left,
    Placement.bottomRight: bottom && right,
    Placement.topCenter: top && center,
    Placement.bottomCenter: bottom && center,
  };
  for (final e in candidates.entries) {
    if (e.value && allowed.contains(e.key)) return e.key;
  }
  return Placement.free;
}
