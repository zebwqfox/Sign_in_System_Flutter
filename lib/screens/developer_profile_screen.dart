import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/top_toast.dart';

class DeveloperProfileScreen extends StatelessWidget {
  const DeveloperProfileScreen({super.key});

  static const String _qq = '1622912909';
  static const String _xHandle = '@zebwqfox';
  static const String _email = '1622912909@qq.com';
  static const String _bili = 'https://space.bilibili.com/107341383';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于开发者')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundImage: AssetImage('assets/app_icon.png'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '音乐生在敲代码是不是很魔幻？',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _contactTile(
                  context,
                  icon: FontAwesomeIcons.qq,
                  label: 'QQ',
                  value: _qq,
                  onTap: () => _copy(context, _qq, label: 'QQ 号'),
                ),
                const Divider(height: 1),
                _contactTile(
                  context,
                  icon: FontAwesomeIcons.xTwitter,
                  label: 'X',
                  value: _xHandle,
                  onTap: () => _openUrl(context, Uri.parse('https://x.com/zebwqfox')),
                ),
                const Divider(height: 1),
                _contactTile(
                  context,
                  icon: FontAwesomeIcons.envelope,
                  label: '邮箱',
                  value: _email,
                  onTap: () => _openUrl(context, Uri.parse('mailto:$_email')),
                ),
                const Divider(height: 1),
                _contactTile(
                  context,
                  icon: FontAwesomeIcons.circlePlay,
                  label: 'Bilibili',
                  value: _bili,
                  onTap: () => _openUrl(context, Uri.parse(_bili)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactTile(
    BuildContext context, {
    required FaIconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: FaIcon(icon, color: cs.primary, size: 18),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Future<void> _copy(
    BuildContext context,
    String text, {
    required String label,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    TopToast.show(context, '$label已复制');
  }

  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok || !context.mounted) return;
    TopToast.show(context, '无法打开链接', error: true);
  }
}
