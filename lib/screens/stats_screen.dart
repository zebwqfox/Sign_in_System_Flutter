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

  @override
  Widget build(BuildContext context) {
    final list = _filtered();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('考勤报表'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '学期统计报表',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${list.length} 人',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                        hintText: '搜索姓名或学号',
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _sortChip('学号', 'id', selectedBg: cs.primary),
                          const SizedBox(width: 8),
                          _sortChip('出勤率', 'rate', selectedBg: cs.primary),
                          const SizedBox(width: 8),
                          _sortChip('缺勤数', 'absent', selectedBg: cs.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        children: const [
                          SizedBox(height: 160),
                          Center(child: CircularProgressIndicator(color: AppTheme.duoGreen)),
                        ],
                      )
                    : list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            children: [
                              const SizedBox(height: 160),
                              Center(
                                child: Text(
                                  '没有找到匹配的学生',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            itemCount: list.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _statsDataRow(list[index]);
                            },
                          ),
              ),
            ),
          ],
        ),
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
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openDetail(s),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.studentName,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (warn)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.duoRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '预警',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.duoRed),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                s.studentId,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 7,
                        color: cs.surfaceContainerHighest,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (s.rate.clamp(0, 100)) / 100.0,
                          child: Container(color: barColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${s.rate}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: warn ? AppTheme.duoRed : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: s.absentCount > 0 ? AppTheme.duoRed.withValues(alpha: 0.10) : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '缺勤 ${s.absentCount}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: s.absentCount > 0 ? AppTheme.duoRed : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
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
    return InkWell(
      onTap: () => _toggleSort(key),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? selectedBg : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: sel ? selectedBg : cs.outlineVariant.withValues(alpha: 0.45)),
        ),
        child: Text(
          '$label$suffix',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: sel ? Colors.white : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(StatsRow s) async {
    context.push(
      '/stats/detail/${Uri.encodeComponent(s.studentId)}/${Uri.encodeComponent(s.studentName)}',
    );
  }
}
