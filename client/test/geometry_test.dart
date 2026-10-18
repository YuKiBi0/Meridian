import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian/settings.dart';
import 'package:meridian/window/geometry.dart';

void main() {
  // 1920x1080 display with a 40px taskbar at the bottom.
  const work = Rect.fromLTWH(0, 0, 1920, 1040);

  test('bars fill the edge inside the margin', () {
    final top = placeView(work, Placement.top, const Size(1904, 8), 8);
    expect(top, const Rect.fromLTWH(8, 8, 1904, 8));
    final right = placeView(work, Placement.right, const Size(8, 1024), 8);
    expect(right, const Rect.fromLTWH(1904, 8, 8, 1024));
    final bottom = placeView(work, Placement.bottom, const Size(1920, 4), 0);
    expect(bottom.bottom, 1040);
  });

  test('corners and centers', () {
    const s = Size(144, 144);
    expect(placeView(work, Placement.bottomRight, s, 16).bottomRight, const Offset(1904, 1024));
    expect(placeView(work, Placement.topCenter, s, 0).center.dx, 960);
  });

  test('free position is clamped on screen', () {
    final r = placeView(work, Placement.free, const Size(144, 144), 8, free: const Offset(1900, -50));
    expect(r.right, 1920);
    expect(r.top, 0);
  });

  test('top bar grows downward for reminders, centered', () {
    final l = layoutFor(work: work, placement: Placement.top, viewSize: const Size(1904, 8), margin: 8, toasts: 1);
    expect(l.toastSide, ToastSide.below);
    expect(l.window.top, 8);
    expect(l.view.top, 0);
    expect(l.toast!.top, 16);
    expect(l.toast!.center.dx + l.window.left, 960);
    expect(l.window.height, 8 + toastGap + toastCardHeight);
  });

  test('bottom-right ring grows up and keeps its spot', () {
    const s = Size(144, 144);
    final plain = layoutFor(work: work, placement: Placement.bottomRight, viewSize: s, margin: 8);
    final l = layoutFor(work: work, placement: Placement.bottomRight, viewSize: s, margin: 8, toasts: 2);
    expect(l.toastSide, ToastSide.above);
    expect(l.view.shift(l.window.topLeft), plain.window);
    expect(l.toast!.right, l.view.right);
    expect(l.toast!.height, toastAreaSize(2).height);
  });

  test('right bar grows to the left', () {
    final l = layoutFor(work: work, placement: Placement.right, viewSize: const Size(8, 1024), margin: 8, toasts: 1);
    expect(l.toastSide, ToastSide.left);
    expect(l.window.right, 1912);
    expect(l.toast!.right + toastGap, l.view.left);
  });

  test('snap after drag', () {
    final allowed = placementsFor[ViewStyle.digits]!;
    expect(snapPlacement(const Rect.fromLTWH(20, 15, 100, 50), work, allowed, 8), Placement.topLeft);
    expect(snapPlacement(const Rect.fromLTWH(910, 1000, 100, 50), work, allowed, 0), Placement.bottomCenter);
    expect(snapPlacement(const Rect.fromLTWH(500, 500, 100, 50), work, allowed, 8), Placement.free);
    expect(snapPlacement(const Rect.fromLTWH(910, 0, 100, 50), work, placementsFor[ViewStyle.ring]!, 0), Placement.free);
  });

  group('corner reminders', () {
    Rect onScreen(Layout l) => l.toast!.shift(l.window.topLeft);

    test('default sits in the top-right corner, away from a bottom-left ring', () {
      final l = layoutFor(
          work: work, placement: Placement.bottomLeft, viewSize: const Size(144, 144), margin: 8, toasts: 2, toastPosition: ToastPosition.topRight);
      expect(onScreen(l).topRight, const Offset(1912, 8));
      expect(l.toastSide, ToastSide.below);
      expect(l.view.shift(l.window.topLeft), const Rect.fromLTWH(8, 888, 144, 144));
      expect(l.window, const Rect.fromLTRB(8, 8, 1912, 1032));
    });

    test('steps below a ring in the same corner', () {
      final l = layoutFor(
          work: work, placement: Placement.topRight, viewSize: const Size(144, 144), margin: 16, toasts: 1, toastPosition: ToastPosition.topRight);
      final t = onScreen(l);
      expect(t.top, 16 + 144 + toastGap);
      expect(t.right, 1904);
    });

    test('steps below a top bar', () {
      final l = layoutFor(
          work: work, placement: Placement.top, viewSize: const Size(1904, 8), margin: 8, toasts: 1, toastPosition: ToastPosition.topRight);
      expect(onScreen(l).top, 16 + toastGap);
      expect(onScreen(l).right, 1912);
    });

    test('steps beside a right bar', () {
      final l = layoutFor(
          work: work, placement: Placement.right, viewSize: const Size(8, 1024), margin: 8, toasts: 1, toastPosition: ToastPosition.topRight);
      final t = onScreen(l);
      expect(t.top, 8);
      expect(t.right, 1904 - toastGap);
    });

    test('bottom corners stack upward', () {
      final l = layoutFor(
          work: work, placement: Placement.top, viewSize: const Size(1904, 8), margin: 0, toasts: 1, toastPosition: ToastPosition.bottomLeft);
      expect(onScreen(l).bottomLeft, const Offset(toastGap, 1040 - toastGap));
      expect(l.toastSide, ToastSide.above);
    });

    test('follow keeps the cards next to the view', () {
      final l = layoutFor(
          work: work, placement: Placement.bottomLeft, viewSize: const Size(144, 144), margin: 8, toasts: 1, toastPosition: ToastPosition.followView);
      expect(onScreen(l).bottom, 888 - toastGap);
      expect(onScreen(l).left, 8);
    });
  });
}
