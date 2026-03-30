import 'dart:async';

import 'package:flutter/widgets.dart';

/// 两帧后再短延时执行，让路由转场动画先走过一截，避免与网络/解析/setState 同帧挤占导致卡顿。
void scheduleAfterTransition(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 90), action));
    });
  });
}
