import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../utils/deferred_work.dart';
import '../utils/haptics.dart';
import '../utils/pinyin_util.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _tts = FlutterTts();
  int _index = 0;
  final List<AttendanceRecord> _records = [];
  bool _submitting = false;

  bool _voice = false;
  bool _pinyin = false;
  bool _showReread = false;
  bool _markNextStartAsStudentName = false;
  bool _awaitingStudentNameUtterance = false;

  bool _reasonOpen = false;
  bool _modifyOpen = false;
  bool _overviewOpen = false;
  bool _customReason = false;
  final _customCtrl = TextEditingController();
  int _modifyingStudentIndex = 0;

  @override
  void initState() {
    super.initState();
    scheduleAfterTransition(() async {
      if (!mounted) return;
      final app = context.read<AppController>();
      final storage = app.storage;
      setState(() {
        _voice = storage.voiceEnabled;
        _pinyin = storage.pinyinEnabled;
      });
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.45);
      _tts.setStartHandler(() {
        if (!mounted) return;
        if (_markNextStartAsStudentName) {
          _awaitingStudentNameUtterance = true;
          _markNextStartAsStudentName = false;
        }
      });
      _tts.setCompletionHandler(() {
        if (!mounted) return;
        final show = _awaitingStudentNameUtterance && _voice;
        _awaitingStudentNameUtterance = false;
        if (show) setState(() => _showReread = true);
      });
      final first = app.students.isEmpty ? null : app.students.first;
      if (first != null && _voice) await _speakStudentName(app, first.name);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _speakOther(String text) async {
    _markNextStartAsStudentName = false;
    _awaitingStudentNameUtterance = false;
    if (mounted) setState(() => _showReread = false);
    if (!_voice || text.isEmpty) return;
    await _tts.stop();
    unawaited(_tts.speak(text));
  }

  /// 朗读当前学生姓名；结束后显示「重读」（与 Web 一致）。
  Future<void> _speakStudentName(AppController app, String name) async {
    if (!_voice || name.isEmpty) return;
    _markNextStartAsStudentName = true;
    if (mounted) setState(() => _showReread = false);
    await _tts.stop();
    unawaited(_tts.speak(name));
  }

  Future<void> _rereadCurrentName(AppController app) async {
    final s = _current(app);
    if (s == null) return;
    await _speakStudentName(app, s.name);
  }

  Student? _current(AppController app) {
    final list = app.students;
    if (list.isEmpty || _index < 0 || _index >= list.length) return null;
    return list[_index];
  }

  List<AttendanceRecord> _dedupe(List<AttendanceRecord> input) {
    final unique = <AttendanceRecord>[];
    final seen = <String>{};
    for (final r in input) {
      if (!seen.contains(r.studentId)) {
        seen.add(r.studentId);
        unique.add(r);
      } else {
        final ix = unique.indexWhere((x) => x.studentId == r.studentId);
        if (ix >= 0) unique[ix] = r;
      }
    }
    return unique;
  }

  void _assignIds(List<AttendanceRecord> list) {
    for (var i = 0; i < list.length; i++) {
      list[i].id ??= i + 1;
    }
  }

  Color _gridColor(String studentId, Color pendingColor) {
    AttendanceRecord? rec;
    for (final r in _records) {
      if (r.studentId == studentId) {
        rec = r;
        break;
      }
    }
    if (rec == null) return pendingColor;
    if (rec.status == 'present') return Colors.green;
    if (rec.status == 'absent') return Colors.red;
    if (rec.status == 'late') return Colors.amber.shade700;
    if (rec.status == 'leave') {
      if (rec.reason.contains('事')) return Colors.purple;
      return Colors.blue;
    }
    return Colors.grey;
  }

  void _pushRecord(AppController app, String status, String reason) {
    final s = _current(app);
    if (s == null) return;
    final ix = _records.indexWhere((r) => r.studentId == s.studentId);
    final row = AttendanceRecord(
      studentId: s.studentId,
      studentName: s.name,
      status: status,
      reason: reason,
    );
    if (ix >= 0) {
      _records[ix] = row;
    } else {
      _records.add(row);
    }
    _next(app);
  }

  Future<void> _next(AppController app) async {
    setState(() {
      _reasonOpen = false;
      _customReason = false;
      _customCtrl.clear();
    });
    final list = app.students;
    if (_index < list.length - 1) {
      setState(() => _index++);
      final s = _current(app);
      if (s != null) await _speakStudentName(app, s.name);
    } else {
      await shortPulse(ms: 45);
      await _finish(app);
    }
  }

  Future<void> _finish(AppController app) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final unique = _dedupe(_records);
      final created = DateTime.now().toUtc().toIso8601String();
      final name = app.draftSessionName;
      try {
        final sid = await app.api.submitSession(
          sessionName: name,
          records: unique,
          createdAtIso: created,
        );
        app.setCompleted(name: name, records: unique, sessionId: '$sid', isLocal: false);
        if (mounted) context.go('/summary');
      } catch (_) {
        _assignIds(unique);
        final pending = LocalPendingSession(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          sessionName: name,
          records: unique,
          createdAt: created,
          totalStudents: unique.length,
          attendanceRate: unique.isEmpty
              ? 0
              : (unique.where((r) => r.status == 'present' || r.status == 'late').length / unique.length),
        );
        final all = await app.storage.loadPendingSessions();
        all.add(pending);
        await app.storage.savePendingSessions(all);
        app.setCompleted(name: name, records: unique, sessionId: pending.id, isLocal: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('网络异常，已保存到本地'), backgroundColor: Colors.orange),
          );
          context.go('/summary');
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onPresent(AppController app) async {
    if (_submitting) return;
    await shortPulse();
    _pushRecord(app, 'present', '');
  }

  Future<void> _onAbsentFlow(AppController app) async {
    if (_submitting) return;
    await shortPulse(ms: 35);
    await _speakOther('未到');
    setState(() => _reasonOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final students = app.students;
    final s = _current(app);
    final progress = students.isEmpty ? 0.0 : _index / students.length;
    final cs = Theme.of(context).colorScheme;
    final pendingGrid = cs.surfaceContainerHighest;

    if (app.draftSessionName.isEmpty || students.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('点名')),
        body: const Center(child: Text('请先返回首页开始会话')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(app.draftSessionName, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _submitting ? null : () => context.go('/'),
        ),
        actions: [
          TextButton(
            onPressed: (_index == 0 || _submitting) ? null : () async {
              await shortPulse();
              setState(() {
                if (_records.isNotEmpty) _records.removeLast();
                _index--;
              });
              final cur = _current(app);
              if (cur != null) await _speakStudentName(app, cur.name);
            },
            child: const Text('撤销'),
          ),
          IconButton(
            tooltip: '拼音',
            onPressed: () async {
              _pinyin = !_pinyin;
              await app.storage.setPinyinEnabled(_pinyin);
              setState(() {});
            },
            icon: Icon(Icons.translate, color: _pinyin ? Colors.purple : null),
          ),
          IconButton(
            tooltip: '朗读',
            onPressed: () async {
              _voice = !_voice;
              await app.storage.setVoiceEnabled(_voice);
              if (!_voice) {
                _markNextStartAsStudentName = false;
                _awaitingStudentNameUtterance = false;
                await _tts.stop();
              }
              setState(() {
                if (!_voice) _showReread = false;
              });
              if (_voice) await _speakOther('语音已开启');
            },
            icon: Icon(_voice ? Icons.volume_up : Icons.volume_off),
          ),
          IconButton(
            tooltip: '总览',
            onPressed: () => setState(() => _overviewOpen = true),
            icon: const Icon(Icons.grid_view),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: cs.surfaceContainerHigh,
                    color: AppTheme.duoGreen,
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxCardW = constraints.maxWidth - 24;
                    return Align(
                      alignment: Alignment.center,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: maxCardW.clamp(0, 560), maxWidth: maxCardW.clamp(0, 560)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                                side: BorderSide(color: AppTheme.duoGreen.withValues(alpha: 0.35), width: 3),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                                child: s == null
                                    ? Text('已完成', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            s.studentId,
                                            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800, fontSize: 16),
                                          ),
                                          if (_pinyin) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              nameToPinyin(s.name),
                                              style: TextStyle(color: AppTheme.duoBlue, fontSize: 24, fontWeight: FontWeight.w800),
                                            ),
                                          ],
                                          const SizedBox(height: 14),
                                          Text(
                                            s.name,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, height: 1.12),
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            '到了吗？',
                                            style: TextStyle(color: AppTheme.duoBlue, fontWeight: FontWeight.w800, fontSize: 20),
                                          ),
                                          if (_showReread && _voice && !_submitting) ...[
                                            const SizedBox(height: 20),
                                            FilledButton.tonalIcon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppTheme.duoBlue.withValues(alpha: 0.15),
                                                foregroundColor: AppTheme.duoBlueDark,
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              ),
                                              onPressed: () => _rereadCurrentName(app),
                                              icon: const Icon(Icons.replay_rounded, size: 26),
                                              label: const Text('重读', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                            ),
                                          ],
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.duoRed.withValues(alpha: 0.12),
                          foregroundColor: AppTheme.duoRed,
                          side: const BorderSide(color: AppTheme.duoRed, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        onPressed: _submitting || s == null ? null : () => _onAbsentFlow(app),
                        child: const Text('未到', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.duoGreen,
                          foregroundColor: Colors.white,
                          shadowColor: AppTheme.duoGreenDark,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        onPressed: _submitting || s == null ? null : () => _onPresent(app),
                        child: const Text('到了', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_reasonOpen && s != null)
            _ReasonSheet(
              studentName: s.name,
              customMode: _customReason,
              customCtrl: _customCtrl,
              onPick: (status, reason) async {
                  await shortPulse();
                  await _speakOther(reason);
                  _pushRecord(app, status, reason);
                },
              onOther: () => setState(() => _customReason = true),
              onCustomConfirm: () async {
                  await shortPulse();
                  await _speakOther('已记录');
                  _pushRecord(app, 'absent', _customCtrl.text.trim().isEmpty ? '其他' : _customCtrl.text.trim());
                },
              onClose: () => setState(() {
                _reasonOpen = false;
                _customReason = false;
                _customCtrl.clear();
              }),
            ),
          if (_modifyOpen)
            _ModifySheet(
              name: _records.isEmpty ? '' : _records[_modifyingStudentIndex.clamp(0, _records.length - 1)].studentName,
              onPick: (status, reason) async {
                if (_modifyingStudentIndex < 0 || _modifyingStudentIndex >= _records.length) return;
                setState(() {
                  final r = _records[_modifyingStudentIndex];
                  r.status = status;
                  r.reason = reason;
                  _modifyOpen = false;
                });
                await shortPulse();
                await _speakOther(reason.isEmpty ? '到了' : reason);
              },
              onClose: () => setState(() => _modifyOpen = false),
            ),
          if (_overviewOpen)
            _OverviewSheet(
              students: students,
              currentIndex: _index,
              pendingColor: pendingGrid,
              colorFor: (id) => _gridColor(id, pendingGrid),
              onClose: () => setState(() => _overviewOpen = false),
              onCellTap: (idx) {
                if (idx >= _records.length) return;
                setState(() {
                  _modifyingStudentIndex = idx;
                  _modifyOpen = true;
                  _overviewOpen = false;
                });
              },
            ),
          if (_submitting) const _SubmittingOverlay(),
        ],
      ),
    );
  }
}

class _ReasonSheet extends StatelessWidget {
  const _ReasonSheet({
    required this.studentName,
    required this.customMode,
    required this.customCtrl,
    required this.onPick,
    required this.onOther,
    required this.onCustomConfirm,
    required this.onClose,
  });

  final String studentName;
  final bool customMode;
  final TextEditingController customCtrl;
  final void Function(String status, String reason) onPick;
  final VoidCallback onOther;
  final VoidCallback onCustomConfirm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$studentName 怎么没来？', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (!customMode)
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.2,
                        children: [
                          _tag(context, '迟到', Colors.amber.shade700, () => onPick('late', '迟到')),
                          _tag(context, '病假', Colors.blue.shade400, () => onPick('leave', '病假')),
                          _tag(context, '事假', Colors.purple, () => onPick('leave', '事假')),
                          _tag(context, '旷课', Colors.red, () => onPick('absent', '旷课')),
                          _tag(context, '其他', Theme.of(context).colorScheme.onSurfaceVariant, onOther),
                        ],
                      )
                    else ...[
                      TextField(
                        controller: customCtrl,
                        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '具体原因'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: onCustomConfirm, child: const Text('确认')),
                    ],
                    TextButton(onPressed: onClose, child: const Text('取消')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label, Color color, VoidCallback onTap) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

class _ModifySheet extends StatelessWidget {
  const _ModifySheet({required this.name, required this.onPick, required this.onClose});

  final String name;
  final void Function(String status, String reason) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Material(
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('修正状态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.4,
                    children: [
                      _mBtn('到了', Colors.green, () => onPick('present', '')),
                      _mBtn('迟到', Colors.amber.shade700, () => onPick('late', '迟到')),
                      _mBtn('病假', Colors.blue.shade400, () => onPick('leave', '病假')),
                      _mBtn('事假', Colors.purple, () => onPick('leave', '事假')),
                      _mBtn('旷课', Colors.red, () => onPick('absent', '旷课')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: onClose, child: const Text('关闭')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mBtn(String label, Color c, VoidCallback fn) {
    return FilledButton(style: FilledButton.styleFrom(backgroundColor: c), onPressed: fn, child: Text(label));
  }
}

class _OverviewSheet extends StatelessWidget {
  const _OverviewSheet({
    required this.students,
    required this.currentIndex,
    required this.pendingColor,
    required this.colorFor,
    required this.onClose,
    required this.onCellTap,
  });

  final List<Student> students;
  final int currentIndex;
  final Color pendingColor;
  final Color Function(String studentId) colorFor;
  final VoidCallback onClose;
  final void Function(int index) onCellTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.close), onPressed: onClose),
                const Expanded(child: Text('点名概览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ],
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: students.length,
                itemBuilder: (ctx, i) {
                  final s = students[i];
                  final bg = colorFor(s.studentId);
                  final cur = i == currentIndex;
                  final light = bg == pendingColor;
                  return GestureDetector(
                    onTap: () => onCellTap(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: light ? bg : bg.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cur ? cs.primary : cs.outlineVariant, width: cur ? 3 : 1),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        s.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: light ? cs.onSurface.withValues(alpha: 0.85) : Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmittingOverlay extends StatelessWidget {
  const _SubmittingOverlay();

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface.withValues(alpha: 0.92);
    return ColoredBox(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('提交中…', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }
}
