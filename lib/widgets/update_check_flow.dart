import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/update_check_models.dart';
import '../services/audit_service.dart';
import '../services/android_package_installer.dart';
import '../services/update_download_service.dart';
import '../services/update_check_service.dart';
import 'top_toast.dart';

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

Future<void> _showUnknownSourceGuideDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('需要安装权限'),
      content: const Text('系统将打开“允许安装未知应用”设置页。\n请为本应用开启权限后返回，再点击“立即下载”。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await AndroidPackageInstaller.openUnknownSourcesSettings();
          },
          child: const Text('去设置'),
        ),
      ],
    ),
  );
}

Future<bool> _downloadAndInstallInApp(BuildContext context, UpdateCheckClientDecision d) async {
  final artifact = d.response.latestRelease?.artifact;
  if (artifact == null) {
    if (context.mounted) {
      TopToast.show(context, '当前版本未提供下载包', error: true);
    }
    return false;
  }
  final uri = Uri.tryParse(artifact.downloadUrl.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    if (context.mounted) {
      TopToast.show(context, '无效的下载地址', error: true);
    }
    return false;
  }

  // 非 Android 或非 APK，仍走系统浏览器下载。
  if (!Platform.isAndroid || artifact.kind.toLowerCase() != 'apk') {
    unawaited(AuditService.instance.logEvent(
      category: 'feature',
      action: 'update_open_external_download',
      feature: 'update',
      extra: {'kind': artifact.kind},
    ));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      TopToast.show(context, '无法打开下载链接', error: true);
    }
    return ok;
  }

  final canInstall = await AndroidPackageInstaller.canRequestPackageInstalls();
  if (!canInstall) {
    unawaited(AuditService.instance.logEvent(
      category: 'feature',
      action: 'update_missing_unknown_sources_permission',
      feature: 'update',
    ));
    if (!context.mounted) return false;
    await _showUnknownSourceGuideDialog(context);
    return false;
  }

  if (!context.mounted) return false;
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('正在下载更新'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (ctx, p, child) {
            final text = p == null ? '准备下载…' : '下载中 ${(p * 100).toStringAsFixed(0)}%';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p),
                const SizedBox(height: 12),
                Text(text),
              ],
            );
          },
        ),
      );
    },
  );

  String? apkPath;
  Object? err;
  try {
    unawaited(AuditService.instance.logEvent(
      category: 'feature',
      action: 'update_download_start',
      feature: 'update',
      extra: {'kind': artifact.kind},
    ));
    apkPath = await UpdateDownloadService().downloadArtifact(
      artifact: artifact,
      onProgress: (p) => progress.value = p,
    );
  } catch (e) {
    err = e;
  } finally {
    progress.dispose();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  if (!context.mounted) return false;
  if (err != null || apkPath == null) {
    TopToast.show(context, '下载失败：$err', error: true);
    return false;
  }

  final canInstallAfterDownload = await AndroidPackageInstaller.canRequestPackageInstalls();
  if (!canInstallAfterDownload) {
    if (!context.mounted) return false;
    await _showUnknownSourceGuideDialog(context);
    return false;
  }

  final started = await AndroidPackageInstaller.installApk(apkPath);
  unawaited(AuditService.instance.logEvent(
    category: 'feature',
    action: started ? 'update_install_intent_started' : 'update_install_intent_failed',
    feature: 'update',
  ));
  if (!context.mounted) return started;
  if (!started) {
    TopToast.show(context, '无法调起系统安装器', error: true);
  } else {
    // 安装器拉起后异步清理临时包，避免缓存长期堆积。
    unawaited(Future<void>.delayed(const Duration(minutes: 8), () async {
      try {
        final f = File(apkPath!);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }));
  }
  return started;
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
                  final shouldClose = await _downloadAndInstallInApp(ctx, d);
                  if (shouldClose && ctx.mounted) Navigator.pop(ctx);
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
    TopToast.show(context, '检查更新失败：$err', error: true);
    return;
  }

  await showUpdateDecisionDialog(context, decision!);
}

/// 关于页展示检查 URL（脱敏说明用）
String updateCheckEndpointHint() => AppConfig.updateCheckUrl;
