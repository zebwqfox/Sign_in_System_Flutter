import 'dart:ui';

import 'package:flutter/material.dart';

/// Liquid Glass 模式下的底栏遮罩：用于视觉收口，让底部区域更“像 iOS 过渡层”，
/// 同时避免全局玻璃化带来的“满屏半透明难看”。
class BottomBarMask extends StatelessWidget {
  const BottomBarMask({super.key, required this.light});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;
    const baseHeight = 72.0;
    final barHeight = baseHeight + bottomInset;

    final bg = light
        ? const Color(0xFFF4F6F8) // 接近你原有浅灰底
        : const Color(0xFF0E1217); // 接近你原有深灰底

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: barHeight,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg.withValues(alpha: light ? 0.88 : 0.86),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Stack(
              children: [
                // 顶部轻微渐变，让“底栏”过渡更柔和
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: light ? 0.06 : 0.30),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // 轻微模糊（可选），让视觉更像“材质”而不是纯色块
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

