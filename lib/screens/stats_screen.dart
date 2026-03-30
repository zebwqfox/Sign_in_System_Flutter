import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../utils/deferred_work.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<StatsRow> _rows = [];
  final _q = TextEditingController();
  String _sortKey = 'rate';
  bool _asc = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    scheduleAfterTransition(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    setState(() => _loading = true);
    try {
      _rows = await app.api.fetchStats();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _asc = !_asc;
      } else {
        _sortKey = key;
        _asc = true;
      }
    });
  }

  List<StatsRow> _filtered() {
    var list = _rows;
    final q = _q.text.trim();
    if (q.isNotEmpty) {
      list = list.where((s) => s.studentName.contains(q) || s.studentId.contains(q)).toList();
    }
    list = [...list]..sort((a, b) {
        num av;
        num bv;
        switch (_sortKey) {
          case 'rate':
            av = a.rate;
            bv = b.rate;
            break;
          case 'absent':
            av = a.absentCount;
            bv = b.absentCount;
            break;
          default:
            av = int.tryParse(a.studentId) ?? 0;
            bv = int.tryParse(b.studentId) ?? 0;
        }
        final c = av.compareTo(bv);
        return _asc ? c : -c;
      });
    return list;
  }

  Map<String, int> _detailCounts(List<Map<String, dynamic>> recs) {
    var present = 0, late = 0, leave = 0, absent = 0;
    for (final r in recs) {
      final st = r['status'] as String? ?? '';
      switch (st) {
        case 'present':
          present++;
          break;
        case 'late':
          late++;
          break;
        case 'leave':
          leave++;
          break;
        case 'absent':
          absent++;
          break;
        default:
          absent++;
      }
    }
    return {'present': present, 'late': late, 'leave': leave, 'absent': absent};
  }

  (String icon, String text, Color fg, Color bg, Color bd) _statusStyle(String status) {
    switch (status) {
      case 'present':
        return ('✅', '出勤', const Color(0xFF16A34A), const Color(0xFFF0FDF4), const Color(0xFFBBF7D0));
      case 'late':
        return ('⚠️', '迟到', const Color(0xFFD97706), const Color(0xFFFEFCE8), const Color(0xFFFDE68A));
      case 'leave':
        return ('📝', '请假', const Color(0xFF2563EB), const Color(0xFFEFF6FF), const Color(0xFFBFDBFE));
      case 'absent':
      default:
        return ('❌', '缺勤', const Color(0xFFDC2626), const Color(0xFFFEF2F2), const Color(0xFFFECACA));
    }
  }

  Future<void> _openDetail(StatsRow s) async {
    final app = context.read<AppController>();
    if (!mounted) return;
    final h = MediaQuery.sizeOf(context).height * 0.88;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sh = Theme.of(ctx).colorScheme;
        return Container(
          height: h,
          decoration: BoxDecoration(
            color: sh.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: sh.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: sh.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: sh.outlineVariant),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                      ),
                      alignment: Alignment.center,
                      child: const Text('🎓', style: TextStyle(fontSize: 28)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.studentName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: sh.onSurface)),
                          const SizedBox(height: 4),
                          Text(s.studentId, style: TextStyle(color: sh.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 28)),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Future<void>.delayed(const Duration(milliseconds: 80)).then((_) {
                    return app.api.fetchStudentRecords(s.studentId);
                  }),
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: AppTheme.duoGreen),
                            const SizedBox(height: 16),
                            Text('加载记录中…', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      );
                    }
                    final recs = snap.data ?? [];
                    if (recs.isEmpty) {
                      return Center(
                        child: Text('暂无考勤记录', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                      );
                    }
                    final c = _detailCounts(recs);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _miniStat('出勤', c['present']!, const Color(0xFF22C55E), const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)),
                              const SizedBox(width: 8),
                              _miniStat('迟到', c['late']!, const Color(0xFFEAB308), const Color(0xFFFEFCE8), const Color(0xFFFEF9C3)),
                              const SizedBox(width: 8),
                              _miniStat('请假', c['leave']!, const Color(0xFF3B82F6), const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)),
                              const SizedBox(width: 8),
                              _miniStat('缺勤', c['absent']!, const Color(0xFFEF4444), const Color(0xFFFEF2F2), const Color(0xFFFECACA)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Container(
                            color: Theme.of(ctx).colorScheme.surface,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: recs.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (ctx, i) {
                                final r = recs[i];
                                final st = r['status'] as String? ?? '';
                                final sty = _statusStyle(st);
                                final timeRaw = r['session_time'];
                                String timeStr;
                                if (timeRaw is String) {
                                  final dt = DateTime.tryParse(timeRaw);
                                  timeStr = dt != null ? _formatLocal(dt) : timeRaw;
                                } else {
                                  timeStr = '$timeRaw';
                                }
                                final reason = (r['reason'] as String?) ?? '';
                                final presentLike = st == 'present';
                                final tctx = Theme.of(ctx).colorScheme;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    if (i < recs.length - 1)
                                      Positioned(
                                        left: 7,
                                        top: 28,
                                        bottom: -20,
                                        child: Container(width: 2, color: tctx.outlineVariant),
                                      ),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 16,
                                          height: 16,
                                          margin: const EdgeInsets.only(top: 6, right: 10),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: st == 'present'
                                                ? tctx.outline
                                                : st == 'absent'
                                                    ? Colors.red.shade400
                                                    : st == 'late'
                                                        ? Colors.amber.shade600
                                                        : Colors.blue.shade400,
                                            border: Border.all(color: tctx.surface, width: 2),
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3)],
                                          ),
                                        ),
                                        Expanded(
                                          child: Material(
                                            color: presentLike ? tctx.surface : tctx.surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: presentLike ? tctx.outlineVariant : tctx.outline,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '${r['session_name'] ?? ''}',
                                                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tctx.onSurface),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: sty.$4,
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: sty.$5),
                                                        ),
                                                        child: Text(
                                                          '${sty.$1} ${sty.$2}',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: sty.$3),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    timeStr,
                                                    style: TextStyle(fontSize: 11, color: tctx.onSurfaceVariant, fontWeight: FontWeight.w600),
                                                  ),
                                                  if (reason.isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: tctx.surface,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: tctx.outlineVariant),
                                                      ),
                                                      child: Text(
                                                        '备注: $reason',
                                                        style: TextStyle(fontSize: 11, color: tctx.onSurface.withValues(alpha: 0.85)),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatLocal(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Widget _miniStat(String label, int value, Color accent, Color bg, Color border) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent.withValues(alpha: 0.85))),
            const SizedBox(height: 4),
            Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.go('/')),
        title: const Text('学期统计报表'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.duoBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('共 ${list.length} 人', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.duoBlueDark)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _q,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.duoBlue),
                hintText: '搜索姓名或学号…',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _sortChip('学号', 'id', selectedBg: const Color(0xFF374151)),
                  const SizedBox(width: 8),
                  _sortChip('出勤率', 'rate', selectedBg: AppTheme.duoBlue),
                  const SizedBox(width: 8),
                  _sortChip('缺勤数', 'absent', selectedBg: AppTheme.duoRed),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.duoGreen))
                : list.isEmpty
                    ? Center(child: Text('没有找到匹配的学生', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)))
                    : Card(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: CustomScrollView(
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(child: _statsTableHeader()),
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final s = list[index];
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (index > 0) Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                                        _statsDataRow(s),
                                      ],
                                    );
                                  },
                                  childCount: list.length,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statsTableHeader() {
    final cs = Theme.of(context).colorScheme;
    final hStyle = TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.onSurface);
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('学生信息', style: hStyle)),
          SizedBox(width: 88, child: Text('出勤率', textAlign: TextAlign.center, style: hStyle)),
          SizedBox(width: 48, child: Text('缺勤', textAlign: TextAlign.right, style: hStyle)),
        ],
      ),
    );
  }

  Widget _statsDataRow(StatsRow s) {
    final warn = s.rate < 60 && s.totalChecks > 0;
    final barColor = s.rate < 60
        ? AppTheme.duoRed
        : s.rate < 90
            ? AppTheme.duoYellow
            : AppTheme.duoGreen;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: () => _openDetail(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onSurface),
                          ),
                          Text(
                            s.studentId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (warn) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.duoRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('预警', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppTheme.duoRed)),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 88,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (s.rate.clamp(0, 100)) / 100.0,
                        minHeight: 6,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: barColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${s.rate}%',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: warn ? AppTheme.duoRed : cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: s.absentCount > 0
                      ? Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.duoRed.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.duoRed.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            '${s.absentCount}',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.duoRed, fontSize: 14),
                          ),
                        )
                      : Text('·', style: TextStyle(fontSize: 22, color: cs.outline, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, String key, {required Color selectedBg}) {
    final sel = _sortKey == key;
    final suffix = sel ? (_asc ? ' ↑' : ' ↓') : '';
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(
        '$label$suffix',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: sel ? Colors.white : cs.onSurfaceVariant),
      ),
      selected: sel,
      onSelected: (_) => _toggleSort(key),
      selectedColor: selectedBg,
      checkmarkColor: Colors.white,
      backgroundColor: cs.surface,
      side: BorderSide(color: cs.outlineVariant),
      showCheckmark: false,
    );
  }
}
