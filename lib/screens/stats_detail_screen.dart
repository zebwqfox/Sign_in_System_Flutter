import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ai_review_service.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../utils/deferred_work.dart';
import '../widgets/top_toast.dart';

class StatsDetailScreen extends StatefulWidget {
  const StatsDetailScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  final String studentId;
  final String studentName;

  @override
  State<StatsDetailScreen> createState() => _StatsDetailScreenState();
}

class _StatsDetailScreenState extends State<StatsDetailScreen> {
  static final DateTime _semesterStart = DateTime(2026, 3, 1);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _records = [];
  bool _semesterOnly = true;
  bool _aiBusy = false;
  bool _aiPanelVisible = false;
  bool _aiPanelExpanded = false;
  String? _aiText;
  Timer? _aiThinkingTimer;
  int _aiThinkingIndex = 0;
  static const List<String> _aiThinkingHints = <String>[
    '猫娘祈祷中...',
    '少女折寿中...',
    '正在翻看这位同学的历史记录喵...',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAiCache());
    scheduleAfterTransition(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _aiThinkingTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _records = await app.api.fetchStudentRecords(widget.studentId);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _aiCacheKey => 'student_${widget.studentId}';

  void _startAiThinkingHints() {
    _aiThinkingTimer?.cancel();
    _aiThinkingTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted || !_aiBusy) return;
      setState(() {
        _aiThinkingIndex = (_aiThinkingIndex + 1) % _aiThinkingHints.length;
      });
    });
  }

  Future<void> _restoreAiCache() async {
    try {
      final cached = await context.read<AppController>().storage.getAiReviewCache(_aiCacheKey);
      if (!mounted || cached == null || cached.trim().isEmpty) return;
      setState(() {
        _aiText = cached;
        _aiPanelVisible = true;
        _aiPanelExpanded = false;
      });
    } catch (_) {}
  }

  Future<void> _runAiReview({bool forceRefresh = false}) async {
    final scoped = _scopedRecords(_records);
    if (scoped.isEmpty || _aiBusy) return;
    final storage = context.read<AppController>().storage;

    if (!forceRefresh) {
      final current = _aiText?.trim() ?? '';
      if (current.isNotEmpty) {
        setState(() {
          _aiPanelVisible = true;
          _aiPanelExpanded = true;
        });
        TopToast.show(context, '已展示本地锐评，点刷新可重新生成');
        return;
      }
      final cached = await storage.getAiReviewCache(_aiCacheKey);
      if (cached != null && cached.trim().isNotEmpty && mounted) {
        setState(() {
          _aiText = cached;
          _aiPanelVisible = true;
          _aiPanelExpanded = true;
        });
        TopToast.show(context, '已使用本地缓存锐评');
        return;
      }
    }

    final m = _AttendanceMetrics.from(scoped);
    final ratePercent = m.total == 0 ? 0 : (((m.present + m.late) / m.total) * 100).round();
    setState(() {
      _aiBusy = true;
      _aiPanelVisible = true;
      _aiPanelExpanded = true;
      _aiText = null;
      _aiThinkingIndex = 0;
    });
    _startAiThinkingHints();
    try {
      final text = await AiReviewService().reviewStudent(
        studentName: widget.studentName,
        studentId: widget.studentId,
        total: m.total,
        present: m.present,
        late: m.late,
        leave: m.leave,
        absent: m.absent,
        ratePercent: ratePercent,
      );
      if (!mounted) return;
      await storage.setAiReviewCache(_aiCacheKey, text);
      setState(() => _aiText = text);
    } catch (e) {
      if (mounted) {
        setState(() => _aiText = '生成失败：$e');
        TopToast.show(context, 'AI 锐评失败：$e', error: true);
      }
    } finally {
      _aiThinkingTimer?.cancel();
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _openStatusSessions(String status) {
    final scoped = _scopedRecords(_records);
    if (scoped.isEmpty) return;
    final label = _statusLabel(status);
    final filtered = scoped.where((r) {
      final s = (r['status'] ?? '').toString();
      if (status == 'absent') return s != 'present' && s != 'late' && s != 'leave';
      return s == status;
    }).toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StatusSessionListScreen(
          studentName: widget.studentName,
          statusLabel: label,
          records: filtered,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _scopedRecords(List<Map<String, dynamic>> source) {
    if (!_semesterOnly) return source;
    return source.where(_isInCurrentSemester).toList();
  }

  bool _isInCurrentSemester(Map<String, dynamic> r) {
    final dt = _parseRecordTime(r);
    if (dt == null) return false;
    return !dt.isBefore(_semesterStart);
  }

  DateTime? _parseRecordTime(Map<String, dynamic> r) {
    final raw = (r['session_time'] ?? r['created_at'] ?? r['createdAt'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }

  Widget _buildAiPanel() {
    final cs = Theme.of(context).colorScheme;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final panelHeight = _aiPanelExpanded ? 300.0 : 64.0;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 10 + bottomSafe,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        offset: _aiPanelVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _aiPanelVisible ? 1 : 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                height: panelHeight,
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.36)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _aiPanelExpanded = !_aiPanelExpanded),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'AI 猫娘锐评',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '重新生成',
                              onPressed: _aiBusy ? null : () => _runAiReview(forceRefresh: true),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                            IconButton(
                              tooltip: _aiPanelExpanded ? '收起' : '展开',
                              onPressed: () => setState(() => _aiPanelExpanded = !_aiPanelExpanded),
                              icon: Icon(
                                _aiPanelExpanded
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.keyboard_arrow_up_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_aiPanelExpanded)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _aiBusy
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      const SizedBox(height: 12),
                                      AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 260),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        child: Text(
                                          _aiThinkingHints[_aiThinkingIndex],
                                          key: ValueKey<int>(_aiThinkingIndex),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : SingleChildScrollView(
                                    child: SelectableText(
                                      _aiText ?? '点上方“猫娘怎么说”，生成本次同学锐评喵',
                                      style: TextStyle(
                                        height: 1.58,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scoped = _scopedRecords(_records);
    return Scaffold(
      appBar: AppBar(
        title: const Text('学生详细信息'),
        actions: [
          if (!_loading && _error == null && scoped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _GradientOutlineAiButton(
                busy: _aiBusy,
                onTap: _aiBusy ? null : _runAiReview,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.duoGreen))
            : _error != null
                ? Center(child: Text('加载失败：$_error', style: TextStyle(color: cs.onSurfaceVariant)))
                : scoped.isEmpty
                    ? Center(
                        child: Text(
                          _semesterOnly ? '本学期暂无考勤记录' : '暂无考勤记录',
                          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.duoGreen,
                        backgroundColor: cs.surfaceContainerLow,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final ui = _AdaptiveUi.fromWidth(c.maxWidth);
                            final metrics = _AttendanceMetrics.from(scoped);
                            final panelPad = _aiPanelVisible ? (_aiPanelExpanded ? 252.0 : 78.0) : 0.0;
                            return CustomScrollView(
                              slivers: [
                                _section(
                                  ui: ui,
                                  top: ui.topSpacing,
                                  bottom: ui.blockSpacing,
                                  child: _HeaderSection(
                                    ui: ui,
                                    studentId: widget.studentId,
                                    studentName: widget.studentName,
                                    recordCount: scoped.length,
                                  ),
                                ),
                                _section(
                                  ui: ui,
                                  bottom: ui.blockSpacing,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        ChoiceChip(
                                          label: const Text('本学期（2026.03.01起）'),
                                          selected: _semesterOnly,
                                          onSelected: (v) => setState(() => _semesterOnly = true),
                                        ),
                                        ChoiceChip(
                                          label: const Text('全部记录'),
                                          selected: !_semesterOnly,
                                          onSelected: (v) => setState(() => _semesterOnly = false),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _section(
                                  ui: ui,
                                  bottom: ui.blockSpacing,
                                  child: _StatGrid(
                                    ui: ui,
                                    metrics: metrics,
                                    onTapStatus: _openStatusSessions,
                                  ),
                                ),
                                _section(
                                  ui: ui,
                                  bottom: ui.itemSpacing,
                                  child: _SectionTitle(ui: ui, title: '考勤记录'),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.symmetric(horizontal: ui.sidePadding),
                                  sliver: SliverList.separated(
                                    itemCount: scoped.length,
                                    separatorBuilder: (_, __) => SizedBox(height: ui.itemSpacing),
                                    itemBuilder: (ctx, i) => Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: ui.maxContentWidth),
                                        child: _RecordCard(ui: ui, record: scoped[i], index: i),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverToBoxAdapter(child: SizedBox(height: ui.bottomSpacing + panelPad)),
                              ],
                            );
                          },
                        ),
                      ),
            ),
            if (_aiPanelVisible) _buildAiPanel(),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _section({
    required _AdaptiveUi ui,
    required Widget child,
    double top = 0,
    double bottom = 0,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(ui.sidePadding, top, ui.sidePadding, bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ui.maxContentWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AdaptiveUi {
  const _AdaptiveUi({
    required this.sidePadding,
    required this.topSpacing,
    required this.blockSpacing,
    required this.itemSpacing,
    required this.bottomSpacing,
    required this.maxContentWidth,
    required this.titleSize,
    required this.subTitleSize,
    required this.bodySize,
    required this.cardRadius,
    required this.gridColumns,
    required this.gridAspectRatio,
  });

  final double sidePadding;
  final double topSpacing;
  final double blockSpacing;
  final double itemSpacing;
  final double bottomSpacing;
  final double maxContentWidth;
  final double titleSize;
  final double subTitleSize;
  final double bodySize;
  final double cardRadius;
  final int gridColumns;
  final double gridAspectRatio;

  static _AdaptiveUi fromWidth(double width) {
    if (width >= 980) {
      return const _AdaptiveUi(
        sidePadding: 26,
        topSpacing: 18,
        blockSpacing: 18,
        itemSpacing: 12,
        bottomSpacing: 28,
        maxContentWidth: 980,
        titleSize: 23,
        subTitleSize: 15,
        bodySize: 13.5,
        cardRadius: 24,
        gridColumns: 4,
        gridAspectRatio: 1.45,
      );
    }
    if (width >= 680) {
      return const _AdaptiveUi(
        sidePadding: 20,
        topSpacing: 16,
        blockSpacing: 14,
        itemSpacing: 9,
        bottomSpacing: 24,
        maxContentWidth: 760,
        titleSize: 19.5,
        subTitleSize: 13.5,
        bodySize: 12.5,
        cardRadius: 22,
        gridColumns: 4,
        gridAspectRatio: 1.34,
      );
    }
    return const _AdaptiveUi(
      sidePadding: 18,
      topSpacing: 12,
      blockSpacing: 10,
      itemSpacing: 8,
      bottomSpacing: 20,
      maxContentWidth: 520,
      titleSize: 17.5,
      subTitleSize: 12.5,
      bodySize: 11.8,
      cardRadius: 18,
      gridColumns: 2,
      gridAspectRatio: 2.5,
    );
  }
}

class _AttendanceMetrics {
  const _AttendanceMetrics({
    required this.total,
    required this.present,
    required this.late,
    required this.leave,
    required this.absent,
  });

  final int total;
  final int present;
  final int late;
  final int leave;
  final int absent;

  static _AttendanceMetrics from(List<Map<String, dynamic>> records) {
    var present = 0;
    var late = 0;
    var leave = 0;
    var absent = 0;
    for (final r in records) {
      switch ((r['status'] ?? '').toString()) {
        case 'present':
          present++;
          break;
        case 'late':
          late++;
          break;
        case 'leave':
          leave++;
          break;
        default:
          absent++;
      }
    }
    return _AttendanceMetrics(
      total: records.length,
      present: present,
      late: late,
      leave: leave,
      absent: absent,
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.ui,
    required this.studentId,
    required this.studentName,
    required this.recordCount,
  });

  final _AdaptiveUi ui;
  final String studentId;
  final String studentName;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ui.cardRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: EdgeInsets.all(ui.sidePadding - 2),
        child: Row(
          children: [
            Container(
              width: ui.titleSize + 26,
              height: ui.titleSize + 26,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Text('🎓', style: TextStyle(fontSize: ui.titleSize + 1)),
            ),
            SizedBox(width: ui.itemSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studentName,
                    style: TextStyle(
                      fontSize: ui.titleSize,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        '学号：$studentId',
                        style: TextStyle(
                          fontSize: ui.subTitleSize,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          '记录 $recordCount',
                          style: TextStyle(
                            fontSize: ui.bodySize,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.ui, required this.title});
  final _AdaptiveUi ui;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: ui.subTitleSize + 1,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.ui,
    required this.metrics,
    required this.onTapStatus,
  });
  final _AdaptiveUi ui;
  final _AttendanceMetrics metrics;
  final ValueChanged<String> onTapStatus;

  @override
  Widget build(BuildContext context) {
    final total = metrics.total;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: ui.gridColumns,
      mainAxisSpacing: ui.itemSpacing,
      crossAxisSpacing: ui.itemSpacing,
      childAspectRatio: ui.gridAspectRatio,
      children: [
        _statMiniCard(
          ui: ui,
          onTap: () => onTapStatus('present'),
          label: '出勤',
          count: metrics.present,
          bg: AppTheme.duoGreen.withValues(alpha: 0.10),
          fg: AppTheme.duoGreenDark,
          accent: AppTheme.duoGreen,
          progress: total == 0 ? 0 : metrics.present / total,
        ),
        _statMiniCard(
          ui: ui,
          onTap: () => onTapStatus('late'),
          label: '迟到',
          count: metrics.late,
          bg: AppTheme.duoYellow.withValues(alpha: 0.12),
          fg: const Color(0xFFB45309),
          accent: AppTheme.duoYellow,
          progress: total == 0 ? 0 : metrics.late / total,
        ),
        _statMiniCard(
          ui: ui,
          onTap: () => onTapStatus('leave'),
          label: '请假',
          count: metrics.leave,
          bg: AppTheme.duoBlue.withValues(alpha: 0.10),
          fg: AppTheme.duoBlueDark,
          accent: AppTheme.duoBlue,
          progress: total == 0 ? 0 : metrics.leave / total,
        ),
        _statMiniCard(
          ui: ui,
          onTap: () => onTapStatus('absent'),
          label: '缺勤',
          count: metrics.absent,
          bg: AppTheme.duoRed.withValues(alpha: 0.10),
          fg: AppTheme.duoRed,
          accent: AppTheme.duoRed,
          progress: total == 0 ? 0 : metrics.absent / total,
        ),
      ],
    );
  }
}

Widget _statMiniCard({
  required _AdaptiveUi ui,
  required VoidCallback onTap,
  required String label,
  required int count,
  required Color bg,
  required Color fg,
  required Color accent,
  required double progress,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(ui.cardRadius - 2),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ui.cardRadius - 2),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        padding: EdgeInsets.all(ui.itemSpacing * 0.82),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: ui.bodySize - 0.3,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: ui.titleSize + 0.6,
                fontWeight: FontWeight.w900,
                color: fg,
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                width: double.infinity,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: accent.withValues(alpha: 0.14),
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.ui,
    required this.record,
    required this.index,
  });

  final _AdaptiveUi ui;
  final Map<String, dynamic> record;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = (record['status'] ?? '') as String;
    final rawStatusText = (record['status_text'] ?? '') as String;
    final statusText = _statusLabel(rawStatusText.isEmpty ? status : rawStatusText);
    final reason = (record['reason'] ?? '') as String;
    final sessionName = (record['session_name'] ?? '') as String;
    final sessionTime = (record['session_time'] ?? '') as String;

    Color chipBg;
    Color chipBorder;
    Color chipText;
    String icon;
    switch (status) {
      case 'present':
        chipBg = AppTheme.duoGreen.withValues(alpha: 0.10);
        chipBorder = AppTheme.duoGreen.withValues(alpha: 0.18);
        chipText = AppTheme.duoGreenDark;
        icon = '✅';
        break;
      case 'late':
        chipBg = AppTheme.duoYellow.withValues(alpha: 0.12);
        chipBorder = AppTheme.duoYellow.withValues(alpha: 0.20);
        chipText = const Color(0xFFB45309);
        icon = '⚠️';
        break;
      case 'leave':
        chipBg = AppTheme.duoBlue.withValues(alpha: 0.10);
        chipBorder = AppTheme.duoBlue.withValues(alpha: 0.20);
        chipText = AppTheme.duoBlueDark;
        icon = '📝';
        break;
      default:
        chipBg = AppTheme.duoRed.withValues(alpha: 0.10);
        chipBorder = AppTheme.duoRed.withValues(alpha: 0.20);
        chipText = AppTheme.duoRed;
        icon = '❌';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: status == 'present' ? cs.surface : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ui.cardRadius - 2),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.42)),
      ),
      padding: EdgeInsets.fromLTRB(
        ui.itemSpacing,
        ui.itemSpacing - 1,
        ui.itemSpacing,
        ui.itemSpacing - 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: ui.bodySize - 0.5,
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ),
          SizedBox(width: ui.itemSpacing - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        sessionName,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: ui.subTitleSize + 0.5,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: chipBorder),
                      ),
                      child: Text(
                        '$icon $statusText',
                        style: TextStyle(
                          color: chipText,
                          fontSize: ui.bodySize - 0.3,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sessionTime,
                  style: TextStyle(
                    fontSize: ui.bodySize,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '备注：${reason.trim()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ui.bodySize,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(String s) {
  switch (s) {
    case 'present':
    case '出勤':
      return '出勤';
    case 'late':
    case '迟到':
      return '迟到';
    case 'leave':
    case '请假':
      return '请假';
    case 'absent':
    case '缺勤':
      return '缺勤';
    default:
      return s;
  }
}

class _StatusSessionListScreen extends StatelessWidget {
  const _StatusSessionListScreen({
    required this.studentName,
    required this.statusLabel,
    required this.records,
  });

  final String studentName;
  final String statusLabel;
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('$studentName · $statusLabel课程')),
      body: records.isEmpty
          ? Center(
              child: Text(
                '暂无$statusLabel课程记录',
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = records[i];
                final sessionName = (r['session_name'] ?? '').toString();
                final sessionTime = (r['session_time'] ?? '').toString();
                final reason = (r['reason'] ?? '').toString().trim();
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
                    title: Text(
                      sessionName.isEmpty ? '未命名课程' : sessionName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      reason.isEmpty ? sessionTime : '$sessionTime\n备注：$reason',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: null,
                    onTap: null,
                  ),
                );
              },
            ),
    );
  }
}

class _GradientOutlineAiButton extends StatefulWidget {
  const _GradientOutlineAiButton({
    required this.busy,
    required this.onTap,
  });

  final bool busy;
  final Future<void> Function()? onTap;

  @override
  State<_GradientOutlineAiButton> createState() => _GradientOutlineAiButtonState();
}

class _GradientOutlineAiButtonState extends State<_GradientOutlineAiButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap == null ? null : () => widget.onTap!.call(),
            borderRadius: BorderRadius.circular(11),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: CustomPaint(
              painter: _GradientOutlinePainter(
                opacity: enabled ? 1 : 0.45,
                shift: _ctrl.value,
              ),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    widget.busy
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onSurface,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '猫娘怎么说',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GradientOutlinePainter extends CustomPainter {
  const _GradientOutlinePainter({
    required this.opacity,
    required this.shift,
  });

  final double opacity;
  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.8), const Radius.circular(11));
    final dx = -size.width + (size.width * 2 * shift);
    final shader = const LinearGradient(
      colors: [
        Color(0xFF4285F4),
        Color(0xFF34A853),
        Color(0xFFFBBC05),
        Color(0xFFEA4335),
      ],
      stops: [0.0, 0.34, 0.66, 1.0],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      tileMode: TileMode.mirror,
    ).createShader(Rect.fromLTWH(dx, 0, size.width, size.height));
    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: opacity);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientOutlinePainter oldDelegate) {
    return oldDelegate.opacity != opacity || oldDelegate.shift != shift;
  }
}

