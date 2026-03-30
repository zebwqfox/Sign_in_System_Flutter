import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/update_check_models.dart';
import '../services/update_check_service.dart';

String _changelogBody(UpdateCheckClientDecision d) {
  final release = d.response.latestRelease;
  if (release == null) return '';
  final buf = StringBuffer();
  buf.writeln('最新版本：${release.semanticVersion}');
  if (release.deliveryMode == 'full') {
    buf.writeln('分发方式：全量包（跨版本升级）');
  } else if (release.deliveryMode == 'delta') {
    buf.writeln('分发方式：增量包（请确认客户端支持）');
  }
  if (d.belowMinSupported) {
    buf.writeln('当前版本低于最低支持线，请尽快更新。');
  }
  if (d.forceUpdate) {
    buf.writeln('策略：必须更新后方可继续使用相关功能。');
  }
  final md = release.changelogMarkdown?.trim();
  if (md != null && md.isNotEmpty) {
    buf.writeln();
    buf.writeln(md);
  } else if (release.changelogEntries.isNotEmpty) {
    buf.writeln();
    for (final e in release.changelogEntries) {
      buf.writeln('• ${e.version}');
      for (final h in e.highlights) {
        buf.writeln('  - $h');
      }
    }
  }
  return buf.toString();
}

/// 根据已拿到的检查结果弹窗（不发起网络）。强制更新且存在下载链时不可返回键关闭。
Future<void> showUpdateDecisionDialog(BuildContext context, UpdateCheckClientDecision d) async {
  final release = d.response.latestRelease;
  if (!d.updateAvailable || release == null) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已是最新版本'),
        content: Text('当前版本：${d.currentVersion}\n${d.compareNote ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
        ],
      ),
    );
    return;
  }

  final trimmedDownloadUrl = release.artifact?.downloadUrl.trim() ?? '';
  final hasUrl = trimmedDownloadUrl.isNotEmpty;
  final mustBlock = d.forceUpdate && hasUrl;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: !mustBlock,
    builder: (ctx) {
      return PopScope(
        canPop: !mustBlock,
        child: AlertDialog(
          title: Text(d.forceUpdate ? '必须更新' : '发现新版本'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(_changelogBody(d)),
            ),
          ),
          actions: [
            if (!mustBlock)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(d.forceUpdate ? '我知道了' : '关闭'),
              ),
            if (hasUrl)
              FilledButton(
                onPressed: () async {
                  final uri = Uri.tryParse(trimmedDownloadUrl);
                  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('无效的下载地址')));
                    }
                    return;
                  }
                  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (!ok && ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(mustBlock ? '立即下载' : '前往下载'),
              )
            else if (d.forceUpdate)
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('我知道了'),
              ),
          ],
        ),
      );
    },
  );
}

/// 在设置页等处触发：拉取远端契约 → 弹窗展示更新说明 / 打开下载链接。
Future<void> runUpdateCheckAndShowDialog(BuildContext context) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('正在检查更新…')),
          ],
        ),
      );
    },
  );

  UpdateCheckClientDecision? decision;
  Object? err;
  try {
    decision = await UpdateCheckService().checkForUpdates();
  } catch (e) {
    err = e;
  }

  if (!context.mounted) return;
  nav.pop();

  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('检查更新失败：$err')),
    );
    return;
  }

  await showUpdateDecisionDialog(context, decision!);
}

/// 关于页展示检查 URL（脱敏说明用）
String updateCheckEndpointHint() => AppConfig.updateCheckUrl;
