import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/course_schedule_service.dart';
import '../state/app_controller.dart';
import '../widgets/top_toast.dart';

class ScheduleManagerScreen extends StatefulWidget {
  const ScheduleManagerScreen({super.key});

  @override
  State<ScheduleManagerScreen> createState() => _ScheduleManagerScreenState();
}

class _ScheduleManagerScreenState extends State<ScheduleManagerScreen> {
  bool _loading = true;
  bool _importing = false;
  List<CourseScheduleItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final app = context.read<AppController>();
    final list = await CourseScheduleService.instance.loadSchedule(app.storage);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _importIcs() async {
    if (_importing) return;
    final app = context.read<AppController>();
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final ext = (file.extension ?? '').toLowerCase();
      if (ext != 'ics') {
        if (mounted) TopToast.show(context, '请选择 .ics 文件', error: true);
        return;
      }
      String? text;
      if (file.bytes != null) {
        text = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null && file.path!.isNotEmpty) {
        text = await File(file.path!).readAsString();
      }
      if (text == null || text.trim().isEmpty) {
        if (mounted) TopToast.show(context, '文件为空或读取失败', error: true);
        return;
      }
      final count = await CourseScheduleService.instance.importFromIcsText(app.storage, text);
      await _reload();
      if (mounted) TopToast.show(context, '导入成功，共 $count 条课表');
    } on MissingPluginException {
      // 插件通道不可用时回退到内置课表，避免导入入口不可用。
      final count = await _importBuiltInIcs(app);
      if (mounted) {
        TopToast.show(context, '文件选择器不可用，已导入内置课表（$count 条）');
      }
    } catch (_) {
      final count = await _importBuiltInIcs(app);
      if (mounted) {
        TopToast.show(context, '导入失败，已回退内置课表（$count 条）', error: true);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clearImported() async {
    final app = context.read<AppController>();
    await CourseScheduleService.instance.clearImportedSchedule(app.storage);
    await _reload();
    if (mounted) TopToast.show(context, '已清空导入课表');
  }

  Future<int> _importBuiltInIcs(AppController app) async {
    final raw = await rootBundle.loadString('class.ics');
    final count = await CourseScheduleService.instance.importFromIcsText(app.storage, raw);
    await _reload();
    return count;
  }

  Future<void> _showIcsGuideDialog() async {
    final step1 = await _resolveAssetPath([
      'assets/step1.png',
      'assets/step1.jpg',
      'assets/step1.jpeg',
      'assets/step1.webp',
      'assets/step1',
    ]);
    final step2 = await _resolveAssetPath([
      'assets/step2.png',
      'assets/step2.jpg',
      'assets/step2.jpeg',
      'assets/step2.webp',
      'assets/step2',
    ]);
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('如何获取 ICS 课表'),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. 打开 WakeUp 课程表，点击右上角分享按钮，导出 iCal 日历文件。',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _guideImage(step1, '步骤1示意图（assets/step1）'),
                const SizedBox(height: 12),
                Text(
                  '2. 选择导出后的 .ics 文件，然后回到本软件点击“导入ICS”。',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _guideImage(step2, '步骤2示意图（assets/step2）'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _guideImage(String? path, String fallbackText) {
    if (path == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        child: Text(
          '$fallbackText（未找到，请把文件放进 assets 目录）',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(path, fit: BoxFit.cover),
    );
  }

  Future<String?> _resolveAssetPath(List<String> candidates) async {
    for (final p in candidates) {
      try {
        await rootBundle.load(p);
        return p;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _mergeRows(_items);
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理课表'),
        actions: [
          TextButton.icon(
            onPressed: _importing ? null : _importIcs,
            icon: _importing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_upload_rounded),
            label: const Text('导入ICS'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '课程名称将按“第n-n节 课程名”生成，用于点名时自动匹配。',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _items.isEmpty ? null : _clearImported,
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _showIcsGuideDialog,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.help_outline_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '不知道 ICS 从哪来？点我查看 WakeUp 导出步骤图',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            '还没有课表，点击右上角导入 .ics',
                            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: rows.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  row.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  '${_weekdayText(row.weekday)} ${_fmtMinute(row.startMinute)}-${_fmtMinute(row.endMinute)}'
                                  '${row.location.isNotEmpty ? ' · ${row.location}' : ''}\n'
                                  '${row.weekRanges.isEmpty ? '周次未标注' : row.weekRanges.join('、')}',
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  static String _weekdayText(int weekday) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final i = weekday.clamp(1, 7) - 1;
    return '周${names[i]}';
  }

  static String _fmtMinute(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  static List<_MergedRow> _mergeRows(List<CourseScheduleItem> items) {
    final map = <String, _MergedRow>{};
    for (final item in items) {
      final key = '${item.displayName}|${item.weekday}|${item.startMinute}|${item.endMinute}|${item.location ?? ''}';
      final row = map.putIfAbsent(
        key,
        () => _MergedRow(
          displayName: item.displayName,
          weekday: item.weekday,
          startMinute: item.startMinute,
          endMinute: item.endMinute,
          location: item.location?.trim() ?? '',
          weekRanges: <String>{},
        ),
      );
      if (item.weekRangeLabel != null && item.weekRangeLabel!.isNotEmpty) {
        row.weekRanges.add(item.weekRangeLabel!);
      }
    }
    final out = map.values.toList();
    out.sort((a, b) {
      final w = a.weekday.compareTo(b.weekday);
      if (w != 0) return w;
      final t = a.startMinute.compareTo(b.startMinute);
      if (t != 0) return t;
      return a.displayName.compareTo(b.displayName);
    });
    return out;
  }
}

class _MergedRow {
  _MergedRow({
    required this.displayName,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.location,
    required this.weekRanges,
  });

  final String displayName;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String location;
  final Set<String> weekRanges;
}
