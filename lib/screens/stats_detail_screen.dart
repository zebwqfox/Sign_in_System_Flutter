import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../utils/deferred_work.dart';

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
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    scheduleAfterTransition(() {
      if (mounted) _load();
    });
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

  @override
  Widget build(BuildContext context) {
    final recordCount = _records.length;
    final sh = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学生详细信息'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.duoGreen))
            : _error != null
                ? Center(
                    child: Text(
                      '加载失败：$_error',
                      style: TextStyle(color: sh.onSurfaceVariant),
                    ),
                  )
                : _records.isEmpty
                    ? Center(
                        child: Text(
                          '暂无考勤记录',
                          style: TextStyle(
                            color: sh.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.duoGreen,
                        backgroundColor: sh.surfaceContainerLow,
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: _HeaderSection(
                                studentId: widget.studentId,
                                studentName: widget.studentName,
                                recordCount: recordCount,
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: 12)),
                            SliverToBoxAdapter(child: _StatGrid(records: _records)),
                            const SliverToBoxAdapter(child: SizedBox(height: 12)),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              sliver: _SectionTitle(title: '考勤记录'),
                            ),
                            SliverList.separated(
                              itemCount: _records.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (ctx, i) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: _RecordTimelineTile(
                                  cs: Theme.of(ctx).colorScheme,
                                  record: _records[i],
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: 20)),
                          ],
                        ),
                      ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.studentId,
    required this.studentName,
    required this.recordCount,
  });
  final String studentId;
  final String studentName;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    final sh = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: sh.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: sh.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: sh.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: sh.outlineVariant),
              ),
              alignment: Alignment.center,
              child: const Text('🎓', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    studentName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: sh.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '学号：$studentId',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: sh.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: sh.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: sh.outlineVariant.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          '记录 $recordCount',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: sh.onSurfaceVariant,
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
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final sh = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: sh.onSurface),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: sh.outlineVariant.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'present': 0,
      'late': 0,
      'leave': 0,
      'absent': 0,
    };
    for (final r in records) {
      final st = (r['status'] ?? '') as String;
      if (counts.containsKey(st)) counts[st] = (counts[st] ?? 0) + 1;
    }

    final total = records.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
        children: [
          _statMiniCard(
            label: '出勤',
            count: counts['present'] ?? 0,
            bg: AppTheme.duoGreen.withValues(alpha: 0.10),
            fg: AppTheme.duoGreenDark,
            accent: AppTheme.duoGreen,
            progress: total == 0 ? 0 : (counts['present'] ?? 0) / total,
          ),
          _statMiniCard(
            label: '迟到',
            count: counts['late'] ?? 0,
            bg: AppTheme.duoYellow.withValues(alpha: 0.12),
            fg: const Color(0xFFB45309),
            accent: AppTheme.duoYellow,
            progress: total == 0 ? 0 : (counts['late'] ?? 0) / total,
          ),
          _statMiniCard(
            label: '请假',
            count: counts['leave'] ?? 0,
            bg: AppTheme.duoBlue.withValues(alpha: 0.10),
            fg: AppTheme.duoBlueDark,
            accent: AppTheme.duoBlue,
            progress: total == 0 ? 0 : (counts['leave'] ?? 0) / total,
          ),
          _statMiniCard(
            label: '缺勤',
            count: counts['absent'] ?? 0,
            bg: AppTheme.duoRed.withValues(alpha: 0.10),
            fg: AppTheme.duoRed,
            accent: AppTheme.duoRed,
            progress: total == 0 ? 0 : (counts['absent'] ?? 0) / total,
          ),
        ],
      ),
    );
  }
}

Widget _statMiniCard({
  required String label,
  required int count,
  required Color bg,
  required Color fg,
  required Color accent,
  required double progress,
}) {
  return Container(
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent.withValues(alpha: 0.16)),
    ),
    padding: const EdgeInsets.all(10),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: fg),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          '$count',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg),
          maxLines: 1,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: accent.withValues(alpha: 0.14),
              color: accent,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecordTimelineTile extends StatelessWidget {
  const _RecordTimelineTile({required this.cs, required this.record});

  final ColorScheme cs;
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
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

    final dotColor = status == 'present'
        ? cs.surfaceContainerHighest
        : (status == 'absent' ? AppTheme.duoRed : (status == 'late' ? AppTheme.duoYellow : AppTheme.duoBlue));

    return LayoutBuilder(
      builder: (context, outer) {
        // 底栏过渡时父约束可能会把 tile 压到很小的 maxHeight（例如 h<=46）。
        // 外层固定 height=86 会导致内部 Column 永远“布局放不下”产生条纹。
        final maxH = outer.maxHeight.isFinite ? outer.maxHeight : 86.0;
        final tileHeight = maxH.clamp(0.0, 86.0);

        return SizedBox(
          height: tileHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          SizedBox(
            width: 44,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor.withValues(alpha: 0.85),
                  border: Border.all(color: cs.surface, width: 2),
                ),
              ),
            ),
          ),
          Expanded(
            child: Card(
              elevation: 0,
              color: status == 'present' ? cs.surface : cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: LayoutBuilder(
                  builder: (context, c) {
                    // 基于当前可用高度选择三档布局，避免过渡帧高度突降导致 Column overflow。
                    final availableH = c.maxHeight.isFinite ? c.maxHeight : 86.0;
                    final isTight = availableH <= 56;
                    final isCompact = !isTight && availableH <= 72;
                    final padding = isTight
                        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                        : (isCompact
                            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                            : const EdgeInsets.all(12));
                    final gap1 = isTight ? 0.0 : (isCompact ? 2.0 : 6.0);
                    final gap2 = isCompact ? 2.0 : 4.0;
                    final titleFontSize = isTight ? 11.0 : (isCompact ? 12.0 : 14.0);
                    final chipFontSize = isTight ? 9.0 : (isCompact ? 10.0 : 12.0);
                    final chipVertical = isTight ? 0.0 : (isCompact ? 1.0 : 4.0);
                    final timeFontSize = isCompact ? 10.0 : 12.0;
                    final reasonText = reason.trim();
                    final hasReason = reasonText.isNotEmpty;

                    final headerRow = LayoutBuilder(
                      builder: (context, w) {
                        final boundedWidth = w.maxWidth.isFinite;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: boundedWidth ? MainAxisSize.max : MainAxisSize.min,
                          children: [
                            boundedWidth
                                ? Expanded(
                                    child: Text(
                                      sessionName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: titleFontSize,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : Flexible(
                                    fit: FlexFit.loose,
                                    child: Text(
                                      sessionName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: titleFontSize,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            const SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: chipVertical),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: chipBorder),
                              ),
                              child: Text(
                                '$icon $statusText',
                                style: TextStyle(
                                  color: chipText,
                                  fontSize: chipFontSize,
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    );

                    final compactLine = Text(
                      hasReason ? '$sessionTime  备注: $reasonText' : sessionTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: timeFontSize, color: cs.onSurfaceVariant),
                    );

                    Widget body;
                    if (isTight) {
                      body = headerRow;
                    } else if (isCompact) {
                      body = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headerRow,
                          SizedBox(height: gap1),
                          compactLine,
                        ],
                      );
                    } else {
                      body = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headerRow,
                          SizedBox(height: gap1),
                          Text(
                            sessionTime,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          if (hasReason) ...[
                            SizedBox(height: gap2),
                            Text(
                              '备注: $reasonText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ],
                      );
                    }

                    return Padding(
                      padding: padding,
                      child: ClipRect(
                        // 兜底：即使过渡帧约束突变，也通过可裁剪滚动容器避免 RenderFlex overflow 断言。
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: body,
                        ),
                      ),
                    );
                  },
                ),
            ),
          ),
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'present':
        return '出勤';
      case 'late':
        return '迟到';
      case 'leave':
        return '请假';
      case 'absent':
        return '缺勤';
      case '出勤':
        return '出勤';
      case '迟到':
        return '迟到';
      case '请假':
        return '请假';
      case '缺勤':
        return '缺勤';
      default:
        return s;
    }
  }
}

