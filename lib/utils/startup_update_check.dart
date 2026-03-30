import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_check_service.dart';
import '../widgets/update_check_flow.dart';

/// 冷启动后延迟执行；**强制更新** 弹不可返回键关闭的对话框；普通更新仅 SnackBar。
void scheduleStartupAppUpdate(
  GlobalKey<ScaffoldMessengerState> messenger,
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

        final url = d.response.latestRelease?.artifact?.downloadUrl.trim();
        final ver = d.response.latestRelease?.semanticVersion ?? '';
        final messengerState = messenger.currentState;
        if (messengerState == null) return;
        messengerState.showSnackBar(
          SnackBar(
            content: Text('发现新版本 $ver，建议更新'),
            duration: const Duration(seconds: 10),
            action: url != null && url.isNotEmpty
                ? SnackBarAction(
                    label: '下载',
                    textColor: Colors.white,
                    onPressed: () {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
                      }
                    },
                  )
                : null,
          ),
        );
      } catch (_) {
        // 启动时不弹失败
      }
    }));
  });
}
