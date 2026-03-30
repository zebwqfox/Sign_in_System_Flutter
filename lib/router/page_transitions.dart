import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 比默认 Material 切换更短、曲线更柔和，减轻「生硬、卡顿」感。
Page<T> fadeSlidePage<T extends Object?>({
  required LocalKey key,
  required Widget child,
  Duration forward = const Duration(milliseconds: 260),
  Duration reverse = const Duration(milliseconds: 200),
  Offset slideBegin = const Offset(0.04, 0),
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: forward,
    reverseTransitionDuration: reverse,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: slideBegin, end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 登录页：几乎无位移，减少等待感。
Page<T> fadePage<T extends Object?>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
