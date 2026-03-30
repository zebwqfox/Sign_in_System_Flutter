import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_mode_bar.dart';
import '../widgets/update_check_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '外观',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('主题', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  ThemeModeBar(app: app),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '「系统」即跟随手机浅色/深色；长按条目可看说明。',
                      style: TextStyle(fontSize: 11, color: muted.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '点名偏好',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.volume_up_rounded, color: AppTheme.duoBlue),
                  title: const Text('语音朗读', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('按人报名时朗读姓名（与点名页一致）'),
                  value: app.voiceEnabled,
                  onChanged: (v) => app.setVoiceEnabled(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.translate_rounded, color: AppTheme.duoGreen),
                  title: const Text('显示拼音', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('在点名卡片上显示姓名拼音'),
                  value: app.pinyinEnabled,
                  onChanged: (v) => app.setPinyinEnabled(v),
                ),
              ],
            ),
          ),
          if (app.debugMode) ...[
            const SizedBox(height: 24),
            Text(
              '开发者',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(Icons.bug_report_outlined, color: AppTheme.duoOrange),
                    title: const Text('调试模式', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '登录失败时显示具体错误信息；便于排查网络与接口。${kDebugMode ? '（当前为 Flutter Debug 构建）' : ''}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    value: app.debugMode,
                    onChanged: (v) => app.setDebugMode(v),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '关于',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('版本'),
                  trailing: Text(app.localVersionLabel, style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.system_update_rounded, color: AppTheme.duoBlue),
                  title: const Text('检查更新', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    updateCheckEndpointHint(),
                    style: TextStyle(fontSize: 11, color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => runUpdateCheckAndShowDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('接口地址'),
                  subtitle: SelectableText(
                    AppConfig.apiBaseUrl,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.85)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('分享页域名'),
                  subtitle: SelectableText(
                    AppConfig.shareBaseUrl,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.85)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '账号',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout_rounded, color: AppTheme.duoRed),
              title: Text('退出登录', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.duoRed)),
              subtitle: const Text('清除本机登录状态'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录？'),
                    content: const Text('需要重新输入密码才能使用管理功能。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.duoRed),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await app.logout();
                  if (context.mounted) context.go('/login');
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => Clipboard.setData(const ClipboardData(text: AppConfig.apiBaseUrl)).then((_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制接口地址')));
                }
              }),
              child: const Text('复制接口地址'),
            ),
          ),
        ],
      ),
    );
  }
}
