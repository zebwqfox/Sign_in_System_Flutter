import 'dart:async';

import 'package:flutter/material.dart';

class TopToast {
  TopToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static Timer? _removeTimer;
  static ValueNotifier<bool>? _visible;

  static void show(
    BuildContext context,
    String message, {
    bool error = false,
    Duration duration = const Duration(milliseconds: 1800),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _timer?.cancel();
    _removeTimer?.cancel();
    _removeNow();

    final visible = ValueNotifier<bool>(false);
    _visible = visible;

    _entry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, show, child) => Positioned(
            left: 14,
            right: 14,
            top: MediaQuery.of(ctx).padding.top + 10,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: show ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    offset: show ? Offset.zero : const Offset(0, -0.12),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: error ? cs.errorContainer : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: error ? cs.error.withValues(alpha: 0.35) : cs.outlineVariant.withValues(alpha: 0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: error ? cs.onErrorContainer : cs.onSurface,
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_visible == visible) visible.value = true;
    });
    _timer = Timer(duration, () {
      _dismissWithAnimation(visible);
    });
  }

  static void _dismissWithAnimation(ValueNotifier<bool> visible) {
    if (_visible != visible) return;
    visible.value = false;
    _removeTimer?.cancel();
    _removeTimer = Timer(const Duration(milliseconds: 190), () {
      if (_visible == visible) {
        _removeNow();
      }
    });
  }

  static void _removeNow() {
    _entry?.remove();
    _entry = null;
    _visible?.dispose();
    _visible = null;
  }
}
