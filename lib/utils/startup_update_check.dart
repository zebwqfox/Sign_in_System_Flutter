import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_check_service.dart';
import '../widgets/top_toast.dart';
import '../widgets/update_check_flow.dart';

/// 冷启动后延迟执行；**强制更新** 弹不可返回键关闭的对话框；普通更新仅顶部轻提示。
void scheduleStartupAppUpdate(
  GlobalKey<NavigatorState> navigatorKey,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 900), () async {
      try {
        final d = await UpdateCheckService().checkForUpdates();
        if (!d.updateAvailable) return;

        if (d.forceUpdate) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            await showUpdateDecisionDialog(ctx, d);
          }
          return;
        }

        final ver = d.response.latestRelease?.semanticVersion ?? '';
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        TopToast.show(ctx, '发现新版本 $ver，建议在设置中检查更新');
      } catch (_) {
        // 启动时不弹失败
      }
    }));
  });
}
