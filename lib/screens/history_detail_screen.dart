import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/ai_review_service.dart';
import '../state/app_controller.dart';
import '../utils/deferred_work.dart';
import '../utils/haptics.dart';
import '../utils/pinyin_util.dart';
import '../theme/app_theme.dart';
import '../widgets/top_toast.dart';

class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({super.key, required this.sessionId, required this.isAdmin});
  final String sessionId;
  final bool isAdmin;
  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  List<AttendanceRecord>? _detail;
  Map<String, dynamic>? _sessionMeta;
  bool _busy = false;
  bool _loadFailed = false;
  String? _loadError;
  bool _sortByPinyinInitial = false;
  String _searchKeyword = '';
  String? _activeIndexLetter;
  Timer? _indexBubbleTimer;
  bool _aiBusy = false;
  bool _aiPanelVisible = false;
  bool _aiPanelExpanded = true;
  String? _aiReviewText;
  Timer? _aiThinkingTimer;
  int _aiThinkingIndex = 0;
  double _aiPanelHideProgress = 0;
  double _lastScrollPixels = 0;
  static const List<String> _aiThinkingHints = <String>[
    '猫娘祈祷中...',
    '少女折寿中...',
    '正在给这节课做灵魂锐评喵...',
    '猫耳雷达分析出勤波动中...',
  ];

  final _editReasonCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final ScrollController _recordsScrollCtrl = ScrollController();
  static final List<String> _azLetters =
      List<String>.generate(26, (i) => String.fromCharCode(65 + i));
  final Map<String, GlobalKey> _letterHeaderKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _recordsScrollCtrl.addListener(_handleRecordsScroll);
    unawaited(_restoreAiReviewCache());
    scheduleAfterTransition(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _indexBubbleTimer?.cancel();
    _aiThinkingTimer?.cancel();
    _recordsScrollCtrl.removeListener(_handleRecordsScroll);
    _editReasonCtrl.dispose();
    _searchCtrl.dispose();
    _recordsScrollCtrl.dispose();
    super.dispose();
  }

  void _handleRecordsScroll() {
    if (!_recordsScrollCtrl.hasClients) return;
    final pixels = _recordsScrollCtrl.position.pixels;
    final delta = pixels - _lastScrollPixels;
    _lastScrollPixels = pixels;
    if (!_aiPanelVisible || delta.abs() < 0.25) return;

    const travel = 140.0;
    var next = _aiPanelHideProgress + (delta / travel);
    if (pixels <= 0) next = 0;
    next = next.clamp(0.0, 1.0);
    if ((next - _aiPanelHideProgress).abs() < 0.006) return;
    if (!mounted) return;
    setState(() => _aiPanelHideProgress = next);
  }

  void _startAiThinkingHints() {
    _aiThinkingTimer?.cancel();
    _aiThinkingTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted || !_aiBusy) return;
      setState(() {
        _aiThinkingIndex = (_aiThinkingIndex + 1) % _aiThinkingHints.length;
      });
    });
  }

  Future<void> _restoreAiReviewCache() async {
    try {
      final cached = await context.read<AppController>().storage.getAiReviewCache(widget.sessionId);
      if (!mounted || cached == null || cached.trim().isEmpty) return;
      setState(() {
        _aiReviewText = cached;
        _aiPanelVisible = true;
        _aiPanelExpanded = false;
        _aiPanelHideProgress = 0;
      });
    } catch (_) {}
  }

  void _scheduleHideIndexBubble([
    Duration delay = const Duration(milliseconds: 620),
  ]) {
    _indexBubbleTimer?.cancel();
    _indexBubbleTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _activeIndexLetter = null);
    });
  }

  String _pinyinInitialKey(String name) {
    final py = nameToPinyin(name).trim().toUpperCase();
    if (py.isEmpty) return '#';
    final ch = py[0];
    return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
  }

  List<AttendanceRecord> _visibleRecords(List<AttendanceRecord> source) {
    final q = _searchKeyword.trim().toLowerCase();
    var out = source;
    if (q.isNotEmpty) {
      out = source.where((r) {
        final name = r.studentName.toLowerCase();
        final sid = r.studentId.toLowerCase();
        final py = nameToPinyin(r.studentName).toLowerCase();
        return name.contains(q) || sid.contains(q) || py.contains(q);
      }).toList();
    } else {
      out = List<AttendanceRecord>.from(source);
    }
    if (_sortByPinyinInitial) {
      out.sort((a, b) {
        final ka = _pinyinInitialKey(a.studentName);
        final kb = _pinyinInitialKey(b.studentName);
        if (ka == '#' && kb != '#') return 1;
        if (kb == '#' && ka != '#') return -1;
        final c = ka.compareTo(kb);
        if (c != 0) return c;
        final pa = nameToPinyin(a.studentName).toLowerCase();
        final pb = nameToPinyin(b.studentName).toLowerCase();
        final cp = pa.compareTo(pb);
        if (cp != 0) return cp;
        return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
      });
    }
    return out;
  }

  List<({String letter, List<AttendanceRecord> records})> _groupByLetter(
    List<AttendanceRecord> records,
  ) {
    final map = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      final k = _pinyinInitialKey(r.studentName);
      map.putIfAbsent(k, () => <AttendanceRecord>[]).add(r);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        if (a == '#' && b != '#') return 1;
        if (b == '#' && a != '#') return -1;
        return a.compareTo(b);
      });
    return keys.map((k) => (letter: k, records: map[k]!)).toList();
  }

  void _jumpByLetter(String touched, Set<String> available) {
    var target = touched;
    if (!available.contains(target)) {
      final idx = _azLetters.indexOf(touched);
      for (var i = idx + 1; i < _azLetters.length; i++) {
        if (available.contains(_azLetters[i])) {
          target = _azLetters[i];
          break;
        }
      }
      if (!available.contains(target)) {
        for (var i = idx - 1; i >= 0; i--) {
          if (available.contains(_azLetters[i])) {
            target = _azLetters[i];
            break;
          }
        }
      }
    }
    final ctx = _letterHeaderKeys[target]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    }
  }

  void _onIndexTouch({
    required double localDy,
    required double boxHeight,
    required Set<String> available,
  }) {
    if (boxHeight <= 0) return;
    final cell = boxHeight / _azLetters.length;
    final idx = (localDy / cell).floor().clamp(0, _azLetters.length - 1);
    final letter = _azLetters[idx];
    if (_activeIndexLetter != letter) {
      setState(() => _activeIndexLetter = letter);
      unawaited(shortPulse(ms: 14));
    }
    _scheduleHideIndexBubble();
    _jumpByLetter(letter, available);
  }

  Widget _buildRecordsList({
    required List<AttendanceRecord> visible,
    required List<({String letter, List<AttendanceRecord> records})> grouped,
  }) {
    if (_sortByPinyinInitial) {
      return Column(
        key: ValueKey('grouped_${_searchKeyword}_${visible.length}'),
        children: grouped.expand((group) {
          final list = <Widget>[
            Padding(
              key: _letterHeaderKeys.putIfAbsent(group.letter, () => GlobalKey()),
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
              child: Row(
                children: [
                  Text(
                    group.letter,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Divider(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55),
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ];
          for (final r in group.records) {
            final idx = visible.indexOf(r);
            list.add(_recordRow(index: idx, record: r));
            list.add(const SizedBox(height: 8));
          }
          return list;
        }).toList(),
      );
    }
    return Column(
      key: ValueKey('plain_${_searchKeyword}_${visible.length}'),
      children: List<Widget>.generate(visible.length, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _recordRow(index: i, record: visible[i]),
        );
      }),
    );
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    final id = widget.sessionId;
    setState(() {
      _busy = true;
      _loadFailed = false;
    });
    try {
      if (id.startsWith('local_')) {
        final all = await app.storage.loadPendingSessions();
        final s = all.firstWhere((e) => e.id == id);
        final recs = s.records.map((e) => e.copy()).toList();
        if (!mounted) return;
        setState(() {
          _detail = recs;
          _sessionMeta = {
            'id': s.id,
            'session_name': s.sessionName,
            'created_at': s.createdAt,
            'total_students': s.totalStudents,
            'attendance_rate': s.attendanceRate,
            'isLocal': true,
          };
        });
      } else {
        final sid = int.parse(id);
        final fetched = widget.isAdmin ? await app.api.fetchSessionDetail(sid) : await app.api.fetchShareSessionDetail(sid);
        if (!mounted) return;
        setState(() {
          _detail = fetched.records;
          _sessionMeta = fetched.session;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loadFailed = true; _loadError = '$e'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncLocalSession() async {
    final meta = _sessionMeta;
    final detail = _detail;
    if (meta == null || meta['isLocal'] != true || detail == null) return;
    final app = context.read<AppController>();
    setState(() => _busy = true);
    try {
      final sessionId = meta['id'] as String;
      final sessionName = meta['session_name'] as String;
      final createdAtIso = meta['created_at'] as String;
      await app.api.submitSession(sessionName: sessionName, records: detail, createdAtIso: createdAtIso);
      await app.storage.removePendingById(sessionId);
      if (mounted) TopToast.show(context, '同步成功');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) TopToast.show(context, '同步失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateRecord({
    required AttendanceRecord target,
    required String newStatus,
    required String newReason,
  }) async {
    final meta = _sessionMeta;
    final app = context.read<AppController>();
    if (meta == null) return;
    setState(() => _busy = true);
    try {
      if (meta['isLocal'] == true) {
        final sessionId = meta['id'] as String;
        final all = await app.storage.loadPendingSessions();
        final idx = all.indexWhere((s) => s.id == sessionId);
        if (idx < 0) return;
        final session = all[idx];

        final rid = target.id;
        if (rid == null) return;
        final recIdx = session.records.indexWhere((r) => r.id == rid);
        if (recIdx < 0) return;

        session.records[recIdx].status = newStatus;
        session.records[recIdx].reason = newReason;

        final total = session.records.length;
        final present = session.records.where((r) => r.status == 'present' || r.status == 'late').length;
        final newRate = total == 0 ? 0.0 : (present / total);

        all[idx] = LocalPendingSession(
          id: session.id,
          sessionName: session.sessionName,
          records: session.records,
          createdAt: session.createdAt,
          totalStudents: session.totalStudents,
          attendanceRate: newRate,
          syncAttempts: session.syncAttempts,
        );

        await app.storage.savePendingSessions(all);

        setState(() {
          target.status = newStatus;
          target.reason = newReason;
          if (_sessionMeta != null) _sessionMeta!['attendance_rate'] = newRate;
        });
      } else {
        final rid = target.id;
        if (rid == null) return;
        final newRate = await app.api.updateRecord(recordId: rid, status: newStatus, reason: newReason);
        setState(() {
          target.status = newStatus;
          target.reason = newReason;
          if (_sessionMeta != null) _sessionMeta!['attendance_rate'] = newRate;
        });
      }

      if (mounted) TopToast.show(context, '修改已保存！');
    } catch (e) {
      if (mounted) TopToast.show(context, '保存失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAiReview({bool forceRefresh = false}) async {
    final detail = _detail;
    final meta = _sessionMeta;
    if (detail == null || meta == null || _aiBusy) return;
    final storage = context.read<AppController>().storage;

    if (!forceRefresh) {
      final current = _aiReviewText?.trim() ?? '';
      if (current.isNotEmpty) {
        setState(() {
          _aiPanelVisible = true;
          _aiPanelExpanded = true;
          _aiPanelHideProgress = 0;
        });
        TopToast.show(context, '已展示本地锐评，点刷新可重新生成');
        return;
      }
      final cached = await storage.getAiReviewCache(widget.sessionId);
      if (cached != null && cached.trim().isNotEmpty && mounted) {
        setState(() {
          _aiReviewText = cached;
          _aiPanelVisible = true;
          _aiPanelExpanded = true;
          _aiPanelHideProgress = 0;
        });
        TopToast.show(context, '已使用本地缓存锐评');
        return;
      }
    }

    final total = detail.length;
    final present = detail.where((r) => r.status == 'present').length;
    final late = detail.where((r) => r.status == 'late').length;
    final leave = detail.where((r) => r.status == 'leave').length;
    final absent = detail.where((r) => r.status != 'present' && r.status != 'late' && r.status != 'leave').length;
    final ratePercent = total == 0 ? 0 : (((present + late) / total) * 100).round();

    final lateNames = detail
        .where((r) => r.status == 'late')
        .map((r) => r.studentName)
        .take(8)
        .toList();
    final absentNames = detail
        .where((r) => r.status != 'present' && r.status != 'late' && r.status != 'leave')
        .map((r) => r.studentName)
        .take(8)
        .toList();

    final sessionName = '${meta['session_name'] ?? '未知课程'}';
    final topLateNames = lateNames.isEmpty ? '无' : lateNames.join('、');
    final topAbsentNames = absentNames.isEmpty ? '无' : absentNames.join('、');

    setState(() {
      _aiBusy = true;
      _aiPanelVisible = true;
      _aiPanelExpanded = true;
      _aiPanelHideProgress = 0;
      _aiReviewText = null;
      _aiThinkingIndex = 0;
    });
    _startAiThinkingHints();
    try {
      final text = await AiReviewService().review(
        sessionName: sessionName,
        total: total,
        present: present,
        late: late,
        leave: leave,
        absent: absent,
        ratePercent: ratePercent,
        topLateNames: topLateNames,
        topAbsentNames: topAbsentNames,
      );
      if (!mounted) return;
      await storage.setAiReviewCache(widget.sessionId, text);
      setState(() => _aiReviewText = text);
    } catch (e) {
      if (mounted) {
        setState(() => _aiReviewText = '生成失败：$e');
        TopToast.show(
          context,
          'AI 评价失败：$e',
          error: true,
        );
      }
    } finally {
      _aiThinkingTimer?.cancel();
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Widget _buildAiReviewPanel() {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final bottomSafe = mq.padding.bottom;
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final filtering = _searchKeyword.trim().isNotEmpty;
    final effectiveVisible = _aiPanelVisible && !keyboardOpen && !filtering;
    final panelHeight = _aiPanelExpanded ? 300.0 : 64.0;
    final easedHide = Curves.easeInCubic.transform(_aiPanelHideProgress.clamp(0, 1));
    final panelOffsetY = effectiveVisible ? easedHide : 1.0;
    final panelOpacity = effectiveVisible ? (1 - easedHide).clamp(0.0, 1.0) : 0.0;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 10 + bottomSafe,
      child: IgnorePointer(
        ignoring: !effectiveVisible || easedHide > 0.92,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          offset: Offset(0, panelOffsetY),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: panelOpacity,
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
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : SingleChildScrollView(
                                    child: SelectableText(
                                      (_aiReviewText ?? '点上方“猫娘怎么说”，生成本次课程锐评喵'),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = _sessionMeta;
    final detail = _detail;
    final visible = detail == null ? const <AttendanceRecord>[] : _visibleRecords(detail);
    final grouped = _sortByPinyinInitial ? _groupByLetter(visible) : const <({String letter, List<AttendanceRecord> records})>[];
    final availableLetters = grouped.map((e) => e.letter).where((e) => e != '#').toSet();
    return Scaffold(
      appBar: AppBar(
        title: Text(_loadFailed ? '加载失败' : '${meta?['session_name'] ?? '考勤详情'}'),
        actions: [
          if (meta != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _GradientOutlineAiButton(
                busy: _aiBusy,
                onTap: _aiBusy ? null : _runAiReview,
              ),
            ),
          if (meta != null && meta['isLocal'] == true && widget.isAdmin)
            IconButton(icon: const Icon(Icons.sync_rounded), onPressed: _syncLocalSession),
          if (meta != null && meta['isLocal'] != true) ...[
            IconButton(icon: const Icon(Icons.download_rounded), onPressed: _exportCsv),
          ],
        ],
      ),
      body: Stack(
        children: [
          if (_busy && detail == null) const Center(child: CircularProgressIndicator())
          else if (_loadFailed) Center(child: Text(_loadError ?? '未知错误'))
          else if (detail != null)
            AnimatedPadding(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                _sortByPinyinInitial ? 44 : 16,
                16,
              ),
              child: SingleChildScrollView(
                controller: _recordsScrollCtrl,
                padding: const EdgeInsets.all(0),
                child: Column(
                  children: [
                    _summaryHeader(detail),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _searchKeyword = v),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText: '搜索姓名 / 学号 / 拼音',
                              suffixIcon: _searchKeyword.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清空',
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchKeyword = '');
                                      unawaited(shortPulse(ms: 12));
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              FilterChip(
                                selected: _sortByPinyinInitial,
                                label: const Text('按拼音首字母排序'),
                                onSelected: (v) {
                                  _indexBubbleTimer?.cancel();
                                  setState(() {
                                    _sortByPinyinInitial = v;
                                    if (!v) _activeIndexLetter = null;
                                  });
                                  unawaited(shortPulse(ms: 18));
                                },
                                avatar: const Icon(Icons.sort_by_alpha_rounded, size: 18),
                              ),
                              Text(
                                '显示 ${visible.length} / ${detail.length}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (widget.isAdmin) ...[
                            const SizedBox(height: 6),
                            Text(
                              '👇 点击学生名字可修正状态',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (currentChild, previousChildren) =>
                          currentChild ?? const SizedBox.shrink(),
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.02),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: _buildRecordsList(visible: visible, grouped: grouped),
                    ),
                  ],
                ),
              ),
            ),
          if (detail != null)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, top: 118, bottom: 26),
                  child: IgnorePointer(
                    ignoring: !_sortByPinyinInitial,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset: _sortByPinyinInitial ? Offset.zero : const Offset(0.65, 0),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        opacity: _sortByPinyinInitial ? 1 : 0,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _onIndexTouch(
                                localDy: d.localPosition.dy,
                                boxHeight: c.maxHeight,
                                available: availableLetters,
                              ),
                              onVerticalDragStart: (d) => _onIndexTouch(
                                localDy: d.localPosition.dy,
                                boxHeight: c.maxHeight,
                                available: availableLetters,
                              ),
                              onVerticalDragUpdate: (d) => _onIndexTouch(
                                localDy: d.localPosition.dy,
                                boxHeight: c.maxHeight,
                                available: availableLetters,
                              ),
                              onTapUp: (_) => _scheduleHideIndexBubble(const Duration(milliseconds: 220)),
                              onTapCancel: () => _scheduleHideIndexBubble(const Duration(milliseconds: 120)),
                              onVerticalDragEnd: (_) => _scheduleHideIndexBubble(const Duration(milliseconds: 120)),
                              onVerticalDragCancel: () => _scheduleHideIndexBubble(const Duration(milliseconds: 120)),
                              child: Container(
                                width: 26,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.70),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: _azLetters.map((l) {
                                    final enabled = availableLetters.contains(l);
                                    final active = _activeIndexLetter == l;
                                    return Text(
                                      l,
                                      style: TextStyle(
                                        fontSize: active ? 10 : 9,
                                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                                        color: enabled
                                            ? Theme.of(context).colorScheme.primary.withValues(alpha: active ? 1 : 0.78)
                                            : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.28),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_activeIndexLetter != null)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 42),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _activeIndexLetter!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_busy && detail != null) const LinearProgressIndicator(),
          if (_aiPanelVisible) _buildAiReviewPanel(),
        ],
      ),
    );
  }

  Widget _summaryHeader(List<AttendanceRecord> d) {
    final total = d.length;
    final presentCount = d.where((r) => r.status == 'present').length;
    final lateCount = d.where((r) => r.status == 'late').length;
    final leaveCount = d.where((r) => r.status == 'leave').length;
    final absentCount = d.where((r) => r.status != 'present' && r.status != 'late' && r.status != 'leave').length;
    final ratePercent = total == 0 ? 0 : (((presentCount + lateCount) / total) * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          _RatePieChart(
            total: total,
            present: presentCount,
            late: lateCount,
            leave: leaveCount,
            absent: absentCount,
            ratePercent: ratePercent,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _LegendDot(label: '出勤', count: presentCount, color: const Color(0xFF22c55e)),
              _LegendDot(label: '迟到', count: lateCount, color: const Color(0xFFEAB308)),
              _LegendDot(label: '请假', count: leaveCount, color: const Color(0xFF3b82f6)),
              _LegendDot(label: '缺勤', count: absentCount, color: const Color(0xFFef4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recordRow({required int index, required AttendanceRecord record}) {
    final cs = _statusColors(record);
    final reasonText = record.reason.trim().isEmpty ? '缺勤' : record.reason.trim();
    final tappable = widget.isAdmin;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: tappable
          ? () async {
              await showGeneralDialog<void>(
                context: context,
                barrierDismissible: true,
                barrierLabel: '修正考勤弹窗',
                barrierColor: Colors.black.withValues(alpha: 0.35),
                transitionDuration: const Duration(milliseconds: 260),
                pageBuilder: (ctx, anim1, anim2) {
                  return _EditRecordDialog(
                    studentName: record.studentName,
                    studentId: record.studentId,
                    initialStatus: record.status,
                    initialReason: record.reason,
                    onConfirm: (status, reason) async {
                      await _updateRecord(target: record, newStatus: status, newReason: reason);
                    },
                  );
                },
                transitionBuilder: (ctx, anim1, anim2, child) {
                  final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
                  return FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                      child: child,
                    ),
                  );
                },
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Text('${index + 1}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontWeight: FontWeight.w900, fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.studentName, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(record.studentId, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (record.status == 'present')
              const Text('✅', style: TextStyle(fontSize: 18))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.bg.withValues(alpha: 1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.fg.withValues(alpha: 0.22)),
                ),
                child: Text(
                  reasonText,
                  style: TextStyle(color: cs.fg, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ({Color fg, Color bg}) _statusColors(AttendanceRecord r) {
    switch (r.status) {
      case 'present':
        return (fg: const Color(0xFF16A34A), bg: const Color(0xFFDCFCE7));
      case 'late':
        return (fg: const Color(0xFFD97706), bg: const Color(0xFFFEF9C3));
      case 'leave':
        return (fg: const Color(0xFF2563EB), bg: const Color(0xFFDBEAFE));
      default:
        return (fg: const Color(0xFFDC2626), bg: const Color(0xFFFEE2E2));
    }
  }

  void _exportCsv() async {
    final d = _detail;
    if (d == null) return;
    final b = StringBuffer('\uFEFF学号,姓名,状态\n');
    for (final r in d) {
      b.write('${r.studentId},${r.studentName},${r.status}\n');
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/export.csv');
    await f.writeAsString(b.toString());
    await Share.shareXFiles([XFile(f.path)]);
  }

}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.95)),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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

class _RatePieChart extends StatelessWidget {
  const _RatePieChart({
    required this.total,
    required this.present,
    required this.late,
    required this.leave,
    required this.absent,
    required this.ratePercent,
  });

  final int total;
  final int present;
  final int late;
  final int leave;
  final int absent;
  final int ratePercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(160, 160),
            painter: _PiePainter(
              present: present,
              late: late,
              leave: leave,
              absent: absent,
            ),
          ),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$ratePercent%',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.duoGreenDark),
                ),
                const SizedBox(height: 4),
                const Text(
                  '出勤率',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.present,
    required this.late,
    required this.leave,
    required this.absent,
  });

  final int present;
  final int late;
  final int leave;
  final int absent;

  @override
  void paint(Canvas canvas, Size size) {
    final total = (present + late + leave + absent);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.92;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    double startAngle = -math.pi / 2;

    void drawSegment(int count, Color color) {
      if (count <= 0) return;
      final sweep = (count / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = color;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }

    drawSegment(present, const Color(0xFF22c55e));
    drawSegment(late, const Color(0xFFEAB308));
    drawSegment(leave, const Color(0xFF3b82f6));
    drawSegment(absent, const Color(0xFFef4444));
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return present != oldDelegate.present || late != oldDelegate.late || leave != oldDelegate.leave || absent != oldDelegate.absent;
  }
}

class _EditRecordDialog extends StatefulWidget {
  const _EditRecordDialog({
    required this.studentName,
    required this.studentId,
    required this.initialStatus,
    required this.initialReason,
    required this.onConfirm,
  });

  final String studentName;
  final String studentId;
  final String initialStatus;
  final String initialReason;
  final Future<void> Function(String status, String reason) onConfirm;

  @override
  State<_EditRecordDialog> createState() => _EditRecordDialogState();
}

class _EditRecordDialogState extends State<_EditRecordDialog> {
  late String _status;
  late final TextEditingController _reasonCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _reasonCtrl = TextEditingController(text: widget.initialReason);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return '出勤';
      case 'late':
        return '迟到';
      case 'leave':
        return '请假';
      default:
        return '缺勤';
    }
  }

  Future<void> _pickStatus(String newStatus) async {
    setState(() => _status = newStatus);
    // Web：如果当前备注看起来是“默认值”（空/状态文案），切换状态就自动重置备注。
    final cur = _reasonCtrl.text.trim();
    final defaultReasons = <String>{
      '',
      _statusLabel('present'),
      _statusLabel('late'),
      _statusLabel('leave'),
      _statusLabel('absent'),
    };
    if (cur.isEmpty || defaultReasons.contains(cur)) {
      _reasonCtrl.text = newStatus == 'present' ? '' : _statusLabel(newStatus);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final reason = _reasonCtrl.text.trim();
      await widget.onConfirm(_status, reason);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = _status;

    FilledButton opt({
      required String status,
      required Color color,
      required String label,
      required IconData icon,
    }) {
      final isOn = selected == status;
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: isOn ? 1 : 0.10),
          foregroundColor: isOn ? Colors.white : color,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.45), width: 2),
          ),
        ),
        onPressed: _busy ? null : () => _pickStatus(status),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isOn ? Colors.white : color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                ),
              ),
              if (isOn) const SizedBox(width: 6),
              if (isOn) const Icon(Icons.check_rounded, size: 16),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Material(
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        color: cs.surface,
        elevation: 10,
        child: Container(
          width: 420,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '修正考勤',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: cs.onSurface),
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.studentName} (${widget.studentId})',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.3,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  opt(
                    status: 'present',
                    color: AppTheme.duoGreen,
                    label: '出勤',
                    icon: Icons.check_circle_rounded,
                  ),
                  opt(
                    status: 'late',
                    color: AppTheme.duoYellow,
                    label: '迟到',
                    icon: Icons.warning_rounded,
                  ),
                  opt(
                    status: 'leave',
                    color: AppTheme.duoBlue,
                    label: '请假',
                    icon: Icons.note_rounded,
                  ),
                  opt(
                    status: 'absent',
                    color: AppTheme.duoRed,
                    label: '缺勤',
                    icon: Icons.cancel_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reasonCtrl,
                decoration: InputDecoration(
                  labelText: '备注 / 原因',
                  hintText: '可为空；不为空将用于记录原因',
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.duoGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('确认修改'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: cs.outlineVariant),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w900)),
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
}
