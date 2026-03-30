import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'student_manager_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _titleTaps = 0;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了，注意休息 🌙';
    if (h < 9) return '早上好，元气满满 ☀️';
    if (h < 12) return '上午好，加油工作 ☕';
    if (h < 14) return '中午好，记得午休 🍱';
    if (h < 18) return '下午好，坚持一下 🚀';
    if (h < 22) return '晚上好，享受生活 🍷';
    return '深夜了，早点睡哦 🛌';
  }

  Future<void> _startSession(BuildContext context, AppController app) async {
    if (app.students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先导入学生名单'), backgroundColor: Colors.red),
      );
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SessionNameDialog(),
    );
    if (name == null || !context.mounted) return;
    app.beginDraftSession(name);
    if (!context.mounted) return;
    context.push('/session');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    final metaStyle = TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '签到助手',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                    ),
                  ),
                  Text('v${app.localVersionLabel}', style: metaStyle),
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.duoGreen,
                            AppTheme.duoGreen.withValues(alpha: 0.85),
                            AppTheme.duoBlue.withValues(alpha: 0.9),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.duoGreen.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _titleTaps++;
                                if (_titleTaps >= 5) {
                                  _titleTaps = 0;
                                  unawaited(app.setDebugMode(true));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('已开启调试模式：设置 → 开发者 可关闭；登录失败将显示详细原因')),
                                    );
                                  }
                                }
                              });
                            },
                            child: Text(
                              '音乐学2专用',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _greeting(),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _heroStat(
                                icon: Icons.groups_rounded,
                                value: app.isHomeDataBootstrapping ? '…' : '${app.students.length}',
                                label: '名册人数',
                              ),
                              const SizedBox(width: 12),
                              _heroStat(
                                icon: (app.busy || app.isHomeDataBootstrapping)
                                    ? Icons.hourglass_top_rounded
                                    : Icons.check_circle_outline_rounded,
                                value: app.busy || app.isHomeDataBootstrapping ? '…' : '就绪',
                                label: app.isHomeDataBootstrapping ? '同步中' : '服务状态',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.duoGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      onPressed: (app.busy || app.isHomeDataBootstrapping) ? null : () => _startSession(context, app),
                      child: const Text('开始新点名', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Text('快捷入口', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.15,
                    ),
                    delegate: SliverChildListDelegate([
                      _quickTile(
                        context,
                        icon: Icons.calendar_month_rounded,
                        title: '历史记录',
                        subtitle: '往日考勤',
                        colors: [const Color(0xFF6366F1), const Color(0xFF818CF8)],
                        onTap: () => context.push('/history'),
                      ),
                      _quickTile(
                        context,
                        icon: Icons.bar_chart_rounded,
                        title: '学期统计',
                        subtitle: '出勤分析',
                        colors: [AppTheme.duoBlue, AppTheme.duoBlue.withValues(alpha: 0.8)],
                        onTap: () => context.push('/stats'),
                      ),
                      _quickTile(
                        context,
                        icon: Icons.receipt_long_rounded,
                        title: '操作日志',
                        subtitle: '审计留痕',
                        colors: [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
                        onTap: () => context.push('/logs'),
                      ),
                      _quickTile(
                        context,
                        icon: Icons.group_rounded,
                        title: '学生名册',
                        subtitle: '导入与编辑',
                        colors: [AppTheme.duoGreenDark, AppTheme.duoGreen],
                        onTap: () => showStudentManagerSheet(context),
                      ),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded, color: AppTheme.duoOrange, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '点名页可在右上角开启拼音与语音；在「设置」里也能随时调整。',
                                style: TextStyle(fontSize: 13, height: 1.35, color: cs.onSurface.withValues(alpha: 0.88), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 28 + MediaQuery.paddingOf(context).bottom),
                    child: TextButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('蒙ICP备2025031646号-1')),
                      ),
                      child: Text('蒙ICP备2025031646号-1', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.65))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat({required IconData icon, required String value, required String label}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const Spacer(),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Controller 生命周期与弹层一致，避免「取消」后立即 dispose 导致 TextField 仍监听。
class _SessionNameDialog extends StatefulWidget {
  const _SessionNameDialog();

  @override
  State<_SessionNameDialog> createState() => _SessionNameDialogState();
}

class _SessionNameDialogState extends State<_SessionNameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    var n = _ctrl.text.trim();
    if (n.isEmpty) {
      final d = DateTime.now();
      n = '${d.month}月${d.day}日点名';
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('这节课叫什么？'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(hintText: '例如：第十二周 道法'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('开始')),
      ],
    );
  }
}
