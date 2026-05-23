import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/audit_service.dart';
import '../services/course_schedule_service.dart';
import '../services/storage_service.dart';
import '../state/app_controller.dart';
import '../state/root_modal_barrier.dart';
import '../widgets/top_toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _hiddenTapCount = 0;
  DateTime _lastHiddenTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _developerTriggeredInBurst = false;

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
    unawaited(
      AuditService.instance.logEvent(
        category: 'feature',
        action: 'tap_start_session',
        feature: 'home',
      ),
    );
    if (app.students.isEmpty) {
      TopToast.show(context, '请先导入学生名单', error: true);
      unawaited(
        AuditService.instance.logEvent(
          category: 'feature',
          action: 'start_session_blocked_no_students',
          feature: 'session',
        ),
      );
      return;
    }
    final name = await _showSessionNameDialog(context, app.storage);
    if (name == null || !context.mounted) return;
    unawaited(
      AuditService.instance.logEvent(
        category: 'feature',
        action: 'start_session_confirmed',
        feature: 'session',
      ),
    );
    app.beginDraftSession(name);
    context.push('/session');
  }

  Future<String?> _showSessionNameDialog(
    BuildContext context,
    StorageService storage,
  ) {
    rootModalBarrierVisible.value = true;
    return showGeneralDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _SessionNameDialog(storage: storage);
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final fade = Tween<double>(begin: 0, end: 1).animate(curved);
        final scale = Tween<double>(begin: 0.96, end: 1.0).animate(curved);
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
    ).whenComplete(() {
      rootModalBarrierVisible.value = false;
    });
  }

  Future<void> _handleTitleTap(AppController app) async {
    final now = DateTime.now();
    if (now.difference(_lastHiddenTapAt) > const Duration(seconds: 2)) {
      _hiddenTapCount = 0;
      _developerTriggeredInBurst = false;
    }
    _lastHiddenTapAt = now;
    _hiddenTapCount++;

    if (!_developerTriggeredInBurst && _hiddenTapCount >= 10) {
      _developerTriggeredInBurst = true;
      unawaited(app.setDebugMode(true));
      if (context.mounted) {
        TopToast.show(context, '已开启调试模式：底栏设置 → 开发者 可关闭');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    const ink = Color(0xFF141C38);
    final bg = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFF7FAFF);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _HomeBackdrop()),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              physics: const BouncingScrollPhysics(),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _handleTitleTap(app),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '签到助手',
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(
                                    color: ink,
                                    fontSize: 32,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            _VersionPill(label: 'v${app.localVersionLabel}'),
                          ],
                        ),
                      ),
                    ),
                    const _NotificationButton(),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _greeting(),
                        style: const TextStyle(
                          color: ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const _CalendarOrbit(size: 116),
                  ],
                ),
                const SizedBox(height: 8),
                _StatusHeroCard(
                  count: app.isHomeDataBootstrapping
                      ? '…'
                      : '${app.students.length}',
                  status: app.isHomeDataBootstrapping ? '同步中' : '已就绪',
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '核心操作', color: cs.primary),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.edit_note_rounded,
                        title: '开始新点名',
                        subtitle: '发起一次即时考勤',
                        color: const Color(0xFF54D665),
                        onTap: (app.busy || app.isHomeDataBootstrapping)
                            ? null
                            : () => _startSession(context, app),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.contacts_rounded,
                        title: '管理学生名册',
                        subtitle: '同步名册或手动编辑',
                        color: const Color(0xFF4E7DFF),
                        onTap: () {
                          unawaited(
                            AuditService.instance.logEvent(
                              category: 'feature',
                              action: 'tap_manage_students',
                              feature: 'home',
                            ),
                          );
                          context.push('/students/manage');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        icon: Icons.calendar_month_rounded,
                        title: '管理课表',
                        subtitle: '用于课程自动匹配',
                        color: const Color(0xFFFF8A1C),
                        onTap: () => context.push('/schedule/manage'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SmartAssistCard(),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    '蒙ICP备2025031646号-1',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.46),
                      fontWeight: FontWeight.w600,
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
}

class _HomeBackdrop extends StatelessWidget {
  const _HomeBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAFCFF), Color(0xFFF4F8FF), Color(0xFFFFFBF6)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -72,
            top: -42,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7D77FF).withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            left: -88,
            top: 214,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF38BDF8).withValues(alpha: 0.11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF6476FF),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IconButton(
            tooltip: '通知',
            onPressed: () {},
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF141C38),
              size: 28,
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4B4B),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarOrbit extends StatelessWidget {
  const _CalendarOrbit({this.size = 110});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 5,
            child: Transform.rotate(
              angle: -0.1,
              child: Container(
                width: size * 0.92,
                height: size * 0.26,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.82),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: 0.15,
            child: Container(
              width: size * 0.60,
              height: size * 0.56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5BFF).withValues(alpha: 0.24),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: size * 0.16,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF8C62FF), Color(0xFF6554F7)],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        width: size * 0.26,
                        height: size * 0.26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8BA2FF), Color(0xFF5965F7)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF5965F7,
                              ).withValues(alpha: 0.26),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: size * 0.18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusHeroCard extends StatelessWidget {
  const _StatusHeroCard({required this.count, required this.status});

  final String count;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF31B7F8), Color(0xFF8A45F8)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B66F6).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -6, top: 12, child: _ShieldOrbit(size: 118)),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: Icons.groups_rounded,
                  label: '名册人数',
                  value: count,
                  foot: '位成员',
                ),
              ),
              Container(
                width: 1,
                height: 86,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: _HeroMetric(
                    icon: Icons.favorite_rounded,
                    label: '服务状态',
                    value: status,
                    foot: '运行中',
                    compactFoot: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.foot,
    this.compactFoot = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String foot;
  final bool compactFoot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        compactFoot
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF44CE69),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      foot,
                      style: const TextStyle(
                        color: Color(0xFF5863E7),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              )
            : Text(
                foot,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ],
    );
  }
}

class _ShieldOrbit extends StatelessWidget {
  const _ShieldOrbit({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 12,
            child: Container(
              width: size * 0.76,
              height: size * 0.14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.1,
            child: Container(
              width: size * 0.86,
              height: size * 0.26,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.86),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Container(
            width: size * 0.64,
            height: size * 0.72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFEFF5FF),
                  Color(0xFF8AA6FF),
                  Color(0xFF6658F6),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.7),
                width: 7,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3327CA).withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Color(0xFF141C38),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 22,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 148,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white, width: 1.6),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF141C38),
                  fontSize: 16,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11.5,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartAssistCard extends StatelessWidget {
  const _SmartAssistCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF17214B),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF17214B).withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF7657FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '实用功能',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 0,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF384A9E), Color(0xFF705CFF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6E5BFF).withValues(alpha: 0.42),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.tips_and_updates_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          Positioned(
            left: 88,
            top: 34,
            right: 98,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '智能辅助 ✦',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '点名时支持拼音辅助与语音播报，\n可通过底栏快速切换至「统计」或「日志」。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 12,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(right: 4, top: 20, bottom: 4, child: _AssistChart()),
          Positioned(
            left: 170,
            bottom: 4,
            child: Row(
              children: List.generate(
                4,
                (index) => Container(
                  width: index == 0 ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 7),
                  decoration: BoxDecoration(
                    color: index == 0
                        ? const Color(0xFF8D63FF)
                        : Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistChart extends StatelessWidget {
  const _AssistChart();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 54,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: const Icon(
                Icons.pie_chart_rounded,
                color: Color(0xFF83A8FF),
                size: 42,
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 52,
              height: 48,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _bar(12),
                  const SizedBox(width: 6),
                  _bar(22),
                  const SizedBox(width: 6),
                  _bar(32),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 8,
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Color(0xFF6476FF),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double h) {
    return Expanded(
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFF80A2FF),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _SessionNameDialog extends StatefulWidget {
  const _SessionNameDialog({required this.storage});

  final StorageService storage;

  @override
  State<_SessionNameDialog> createState() => _SessionNameDialogState();
}

class _SessionNameDialogState extends State<_SessionNameDialog> {
  late final TextEditingController _ctrl;
  String? _autoMatchedName;
  bool _matching = true;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    unawaited(_tryAutoFillCourseName());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('这节课叫什么？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '例如：第十二周 道法',
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.primary, width: 1.6),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          if (_matching)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在按上课时间匹配课程…',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else if (_autoMatchedName != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '已自动匹配：$_autoMatchedName',
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('开始')),
      ],
    );
  }

  void _submit() {
    var n = _ctrl.text.trim();
    if (n.isEmpty) {
      final d = DateTime.now();
      n = '${d.month}月${d.day}日点名';
    }
    Navigator.pop(context, n);
  }

  Future<void> _tryAutoFillCourseName() async {
    try {
      final matched = await CourseScheduleService.instance.matchCourseNameNow(
        widget.storage,
        DateTime.now(),
      );
      if (!mounted) return;
      if (matched != null && _ctrl.text.trim().isEmpty) {
        _ctrl.text = matched;
        _ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _ctrl.text.length),
        );
      }
      setState(() {
        _autoMatchedName = matched;
        _matching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _matching = false;
      });
    }
  }
}
