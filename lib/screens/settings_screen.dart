import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/top_toast.dart';
import '../widgets/theme_mode_bar.dart';
import '../widgets/update_check_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<Color> _themeSeedColors = [
    Color(0xFF58CC02),
    Color(0xFF1CB0F6),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _sectionHeader(muted, '点名偏好'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const FaIcon(FontAwesomeIcons.volumeHigh, color: AppTheme.duoBlue, size: 18),
                  title: const Text('语音朗读', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('按人报名时朗读姓名'),
                  value: app.voiceEnabled,
                  onChanged: (v) => app.setVoiceEnabled(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const FaIcon(FontAwesomeIcons.language, color: AppTheme.duoGreen, size: 18),
                  title: const Text('显示拼音', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('在点名卡片上显示姓名拼音'),
                  value: app.pinyinEnabled,
                  onChanged: (v) => app.setPinyinEnabled(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(muted, '外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  ThemeModeBar(app: app),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          selected: app.themeColorMode == 'monet',
                          label: const Text('莫奈动态取色'),
                          onSelected: (v) {
                            if (v) app.setThemeColorMode('monet');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          selected: app.themeColorMode == 'custom',
                          label: const Text('自选主题色'),
                          onSelected: (v) {
                            if (v) app.setThemeColorMode('custom');
                          },
                        ),
                      ),
                    ],
                  ),
                  if (app.themeColorMode == 'custom') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _themeSeedColors.map((c) {
                        final on = app.themeSeedColor == c.toARGB32();
                        return GestureDetector(
                          onTap: () => app.setThemeSeedColor(c.toARGB32()),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: on ? cs.onSurface : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: on
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    app.themeColorMode == 'monet'
                        ? 'Android 12+ 自动跟随系统壁纸取色，不支持时自动回退默认主题。'
                        : '已使用手动主题色，优先级高于莫奈动态色。',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.blur_on_rounded, size: 18),
                      title: const Text('iOS Liquid Glass', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('开启后底栏使用更强的原生液态玻璃效果'),
                      value: app.liquidGlassEnabled,
                      onChanged: (v) => app.setLiquidGlassEnabled(v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(muted, '开发者'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const FaIcon(FontAwesomeIcons.bug, color: AppTheme.duoOrange, size: 18),
                  title: const Text('调试模式', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('登录失败时显示具体错误信息', style: TextStyle(fontSize: 12, color: muted)),
                  value: app.debugMode,
                  onChanged: (v) => app.setDebugMode(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(muted, '关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.circleInfo, size: 18),
                  title: const Text('版本'),
                  trailing: Text(app.localVersionLabel, style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.fileContract, size: 18, color: AppTheme.duoBlueDark),
                  title: const Text('用户协议', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => context.push('/legal/user-agreement'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.shieldHalved, size: 18, color: AppTheme.duoGreenDark),
                  title: const Text('隐私政策', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => context.push('/legal/privacy-policy'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.arrowsRotate, color: AppTheme.duoBlue, size: 18),
                  title: const Text('检查更新', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => runUpdateCheckAndShowDialog(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const FaIcon(FontAwesomeIcons.userTie, color: AppTheme.duoGreenDark, size: 18),
                  title: const Text('关于开发者', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('头像、格言与联系方式'),
                  onTap: () => context.push('/about/developer'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(muted, '账号'),
          Card(
            child: ListTile(
              leading: const FaIcon(FontAwesomeIcons.rightFromBracket, color: AppTheme.duoRed, size: 18),
              title: const Text('退出登录', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.duoRed)),
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
          const SizedBox(height: 48),
          Center(
            child: TextButton(
              onPressed: () => Clipboard.setData(const ClipboardData(text: AppConfig.apiBaseUrl)).then((_) {
                if (context.mounted) {
                  TopToast.show(context, '已复制接口地址');
                }
              }),
              child: const Text('复制接口地址'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(Color muted, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted),
      ),
    );
  }
}
