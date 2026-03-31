import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _confettiCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _confettiPlayed = false;

  @override
  void dispose() {
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final name = app.completedSessionName;
    final records = app.completedRecords;
    final isLocal = app.completedIsLocal;
    final p = records.where((r) => r.status == 'present' || r.status == 'late').length;
    final rate = records.isEmpty ? 0 : (p / records.length * 100).round();
    final abnormal = records.where((r) => r.status != 'present').toList();
    final abnormalGroups = _groupAbnormalByStatus(abnormal);
    final isPerfect = records.isNotEmpty && abnormal.isEmpty;

    if (isPerfect && !_confettiPlayed) {
      _confettiPlayed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _confettiCtrl.forward(from: 0);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('点名结算')),
      body: Stack(
        children: [
          ColoredBox(
            color: const Color(0xFFF0FAF2),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppTheme.duoGreenDark),
                      ),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(color: AppTheme.duoGreen, fontWeight: FontWeight.w900),
                          children: [
                            TextSpan(text: '$rate', style: const TextStyle(fontSize: 66)),
                            const TextSpan(text: '%', style: TextStyle(fontSize: 34)),
                          ],
                        ),
                      ),
                      const Text(
                        '出勤率',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.duoGreenDark),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (isLocal) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDBA74)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text('⏳', style: TextStyle(fontSize: 20)),
                            SizedBox(width: 8),
                            Text('已保存到本地', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF9A3412))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '网络异常，点名记录已暂存。请稍后到历史记录页同步到服务器。',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => context.push('/history'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFB923C),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('前往历史记录同步'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        color: const Color(0xFFDCFCE7),
                        borderColor: const Color(0xFF86EFAC),
                        textColor: const Color(0xFF15803D),
                        icon: Icons.upload_file_rounded,
                        label: '导出 Excel',
                        onTap: () => _exportCsv(records, name),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD1FAE5), width: 2),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('异常名单', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF374151))),
                      const SizedBox(height: 8),
                      Divider(color: Colors.grey.shade300, height: 1),
                      const SizedBox(height: 10),
                      if (abnormal.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Text('🎉 全员全勤！', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF6B7280))),
                          ),
                        )
                      else
                        ...abnormalGroups.entries.expand((entry) {
                          final groupTitle = _groupTitle(entry.key);
                          final rows = entry.value;
                          return <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 8),
                              child: Row(
                                children: [
                                  Text(
                                    groupTitle,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
                                ],
                              ),
                            ),
                            ...rows.map(
                              (r) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Text(
                                      r.studentId,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF9CA3AF),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        r.studentName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    _reasonBadge(_statusReason(r)),
                                  ],
                                ),
                              ),
                            ),
                          ];
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF6B7280),
                    side: BorderSide(color: Colors.grey.shade300, width: 2),
                  ),
                  child: const Text('完成并返回'),
                ),
              ],
            ),
          ),
          if (isPerfect) IgnorePointer(child: _ConfettiBurst(animation: _confettiCtrl)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'present' => '出勤',
      'late' => '迟到',
      'leave' => '请假',
      _ => '缺勤',
    };
  }

  String _statusReason(AttendanceRecord r) {
    final reason = r.reason.trim();
    if (reason.isNotEmpty) return reason;
    return _statusLabel(r.status);
  }

  Map<String, List<AttendanceRecord>> _groupAbnormalByStatus(List<AttendanceRecord> rows) {
    final map = <String, List<AttendanceRecord>>{
      'late': <AttendanceRecord>[],
      'leave': <AttendanceRecord>[],
      'absent': <AttendanceRecord>[],
      'other': <AttendanceRecord>[],
    };
    for (final r in rows) {
      if (r.status == 'late') {
        map['late']!.add(r);
      } else if (r.status == 'leave') {
        map['leave']!.add(r);
      } else if (r.status == 'absent') {
        map['absent']!.add(r);
      } else {
        map['other']!.add(r);
      }
    }
    map.removeWhere((key, value) => value.isEmpty);
    return map;
  }

  String _groupTitle(String status) {
    return switch (status) {
      'late' => '迟到',
      'leave' => '请假',
      'absent' => '缺勤',
      _ => '其他',
    };
  }

  Widget _actionButton({
    required Color color,
    required Color borderColor,
    required Color textColor,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasonBadge(String text) {
    Color bg = const Color(0xFFFEE2E2);
    Color fg = const Color(0xFFDC2626);
    if (text.contains('迟')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
    } else if (text.contains('假')) {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF2563EB);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }

  Future<void> _exportCsv(List<AttendanceRecord> records, String sessionName) async {
    final b = StringBuffer('\uFEFF学号,姓名,状态,备注\n');
    for (final r in records) {
      final status = _statusLabel(r.status);
      final reason = r.reason.trim();
      b.write('${r.studentId},${r.studentName},$status,$reason\n');
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${sessionName}_考勤表.csv');
    await f.writeAsString(b.toString());
    await Share.shareXFiles([XFile(f.path)]);
  }
}

class _ConfettiBurst extends StatelessWidget {
  const _ConfettiBurst({required this.animation});

  final Animation<double> animation;

  static const _icons = ['🎉', '✨', '🎊', '🌟'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOut.transform(animation.value).clamp(0.0, 1.0);
        return LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight;
            final w = c.maxWidth;
            final children = <Widget>[];
            for (var i = 0; i < 28; i++) {
              final seed = (i * 0.61803398875) % 1;
              final x = seed * w;
              final drift = math.sin((t * 5) + i) * 26;
              final y = -20 + (h + 80) * t + (i % 4) * 14;
              final rot = (t * 2 * math.pi) + i * 0.25;
              final opacity = (1 - (t - 0.78).clamp(0, 1)).toDouble();
              children.add(
                Positioned(
                  left: (x + drift).clamp(0, w - 24),
                  top: y,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      angle: rot,
                      child: Text(
                        _icons[i % _icons.length],
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Stack(children: children);
          },
        );
      },
    );
  }
}
