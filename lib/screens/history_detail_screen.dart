import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../utils/deferred_work.dart';

/// 班会考勤详情（管理员从历史进入 / 访客从分享链接进入）。
class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({super.key, required this.sessionId, required this.isAdmin});

  /// 服务端会话为数字字符串；本地未同步为 `local_*`。
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

  AttendanceRecord? _editing;
  String _editStatus = 'present';
  final _editReasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    scheduleAfterTransition(() {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _editReasonCtrl.dispose();
    super.dispose();
  }

  void _ensureIds(List<AttendanceRecord> list) {
    for (var i = 0; i < list.length; i++) {
      list[i].id ??= i + 1;
    }
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    final id = widget.sessionId;
    setState(() {
      _busy = true;
      _loadFailed = false;
      _loadError = null;
    });
    try {
      if (id.startsWith('local_')) {
        final all = await app.storage.loadPendingSessions();
        LocalPendingSession? s;
        for (final e in all) {
          if (e.id == id) {
            s = e;
            break;
          }
        }
        if (s == null) throw ApiException('本地记录不存在');
        final localSession = s;
        final recs = localSession.records.map((e) => e.copy()).toList();
        _ensureIds(recs);
        if (!mounted) return;
        setState(() {
          _detail = recs;
          _sessionMeta = {
            'id': localSession.id,
            'session_name': localSession.sessionName,
            'created_at': localSession.createdAt,
            'total_students': localSession.totalStudents,
            'attendance_rate': localSession.attendanceRate,
            'isLocal': true,
          };
        });
      } else {
        final sid = int.tryParse(id);
        if (sid == null) throw ApiException('无效会话');
        final fetched = widget.isAdmin ? await app.api.fetchSessionDetail(sid) : await app.api.fetchShareSessionDetail(sid);
        if (!mounted) return;
        setState(() {
          _detail = fetched.records;
          _sessionMeta = fetched.session;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loadError = '$e';
        _detail = null;
        _sessionMeta = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncLocal() async {
    final meta = _sessionMeta;
    if (meta == null || meta['isLocal'] != true) return;
    final sid = meta['id'] as String;
    final app = context.read<AppController>();
    final all = await app.storage.loadPendingSessions();
    LocalPendingSession? local;
    for (final e in all) {
      if (e.id == sid) {
        local = e;
        break;
      }
    }
    if (local == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地会话不存在')));
      return;
    }
    setState(() => _busy = true);
    try {
      await app.api.submitSession(sessionName: local.sessionName, records: local.records, createdAtIso: local.createdAt);
      await app.storage.removePendingById(local.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同步成功')));
      context.pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRecordEdit() async {
    final rec = _editing;
    final meta = _sessionMeta;
    final detail = _detail;
    if (rec == null || meta == null || detail == null) return;
    if (rec.id == null) _ensureIds(detail);
    final app = context.read<AppController>();
    setState(() => _busy = true);
    try {
      if (meta['isLocal'] == true) {
        final all = await app.storage.loadPendingSessions();
        LocalPendingSession? sess;
        for (final e in all) {
          if (e.id == meta['id']) {
            sess = e;
            break;
          }
        }
        if (sess == null) throw ApiException('本地会话不存在');
        final local = sess;
        final target = local.records.firstWhere((r) => r.id == rec.id);
        target.status = _editStatus;
        target.reason = _editReasonCtrl.text;
        final total = local.records.length;
        final pr = local.records.where((r) => r.status == 'present' || r.status == 'late').length;
        final updated = LocalPendingSession(
          id: local.id,
          sessionName: local.sessionName,
          records: local.records,
          createdAt: local.createdAt,
          totalStudents: total,
          attendanceRate: total == 0 ? 0 : pr / total,
          syncAttempts: local.syncAttempts,
        );
        final ix = all.indexWhere((e) => e.id == local.id);
        all[ix] = updated;
        await app.storage.savePendingSessions(all);
        setState(() {
          _editing = null;
          _sessionMeta = {...meta, 'attendance_rate': updated.attendanceRate};
          _detail = updated.records.map((e) => e.copy()).toList();
        });
      } else {
        final rid = rec.id;
        if (rid == null) return;
        await app.api.updateRecord(recordId: rid, status: _editStatus, reason: _editReasonCtrl.text);
        final dr = _detail!;
        final t = dr.firstWhere((r) => r.id == rec.id);
        t.status = _editStatus;
        t.reason = _editReasonCtrl.text;
        setState(() => _editing = null);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _detailRate() {
    final d = _detail;
    if (d == null || d.isEmpty) return 0;
    final p = d.where((r) => r.status == 'present' || r.status == 'late').length;
    return ((p / d.length) * 100).round();
  }

  ({Color bar, Color pillBg, Color pillFg, String label}) _recordStatusColors(AttendanceRecord r) {
    switch (r.status) {
      case 'present':
        return (
          bar: const Color(0xFF22C55E),
          pillBg: const Color(0xFFDCFCE7),
          pillFg: const Color(0xFF166534),
          label: '出勤',
        );
      case 'late':
        return (
          bar: const Color(0xFFEAB308),
          pillBg: const Color(0xFFFEF9C3),
          pillFg: const Color(0xFFA16207),
          label: '迟到',
        );
      case 'leave':
        return (
          bar: const Color(0xFF3B82F6),
          pillBg: const Color(0xFFDBEAFE),
          pillFg: const Color(0xFF1D4ED8),
          label: '请假',
        );
      case 'absent':
      default:
        return (
          bar: const Color(0xFFEF4444),
          pillBg: const Color(0xFFFEE2E2),
          pillFg: const Color(0xFFB91C1C),
          label: '缺勤',
        );
    }
  }

  Map<String, int> _detailStatusCounts() {
    final d = _detail;
    var present = 0, late = 0, leave = 0, absent = 0;
    if (d == null) return {'present': 0, 'late': 0, 'leave': 0, 'absent': 0};
    for (final r in d) {
      switch (r.status) {
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

  Widget _detailSummaryHeader() {
    final c = _detailStatusCounts();
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 164,
            height: 164,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(164, 164),
                  painter: _AttendancePiePainter(
                    counts: c,
                    emptyRingColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surface),
                  alignment: Alignment.center,
                  child: Text(
                    '${_detailRate()}%',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _legendRow('出勤', c['present']!, const Color(0xFF22C55E)),
              _legendRow('迟到', c['late']!, const Color(0xFFEAB308)),
              _legendRow('请假', c['leave']!, const Color(0xFF3B82F6)),
              _legendRow('缺勤', c['absent']!, const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRecordCard(AttendanceRecord r, bool admin) {
    final st = _recordStatusColors(r);
    final reason = r.reason.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: admin ? () => _showRecordEditor(r) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: st.bar,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.studentName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.studentId,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    constraints: const BoxConstraints(minWidth: 48),
                    decoration: BoxDecoration(
                      color: st.pillBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: st.pillFg.withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      st.label,
                      style: TextStyle(color: st.pillFg, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRecordEditor(AttendanceRecord r) async {
    _editing = r;
    _editReasonCtrl.text = r.reason;
    var st = r.status;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: Text('修正 ${r.studentName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in [
                        {'k': 'present', 'l': '出勤'},
                        {'k': 'late', 'l': '迟到'},
                        {'k': 'leave', 'l': '请假'},
                        {'k': 'absent', 'l': '缺勤'},
                      ])
                        FilterChip(
                          label: Text(o['l']!),
                          selected: st == o['k'],
                          onSelected: (_) => setD(() => st = o['k']!),
                        ),
                    ],
                  ),
                  TextField(controller: _editReasonCtrl, decoration: const InputDecoration(labelText: '备注')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  _editStatus = st;
                  Navigator.pop(ctx);
                  _saveRecordEdit();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportDetailCsv() async {
    final d = _detail;
    final m = _sessionMeta;
    if (d == null || m == null) return;
    final name = '${m['session_name']}';
    final b = StringBuffer('\uFEFF学号,姓名,状态,备注\n');
    for (final r in d) {
      final sm = {'present': '出勤', 'late': '迟到', 'leave': '请假', 'absent': '缺勤'}[r.status] ?? '缺勤';
      b.write('${r.studentId},${r.studentName},$sm,${r.reason}\n');
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${name}_考勤.csv');
    await f.writeAsString(b.toString());
    await Share.shareXFiles([XFile(f.path)]);
  }

  Widget _legendRow(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        Text(' $count', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: color)),
      ],
    );
  }

  void _shareDetail() {
    final m = _sessionMeta;
    if (m == null || m['isLocal'] == true) return;
    final id = m['id'];
    final shareUrl = '${AppConfig.shareBaseUrl}/share?share_id=$id';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('分享'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: shareUrl, size: 200),
            SelectableText(shareUrl, style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareUrl));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('复制'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.isAdmin;
    final meta = _sessionMeta;
    final detail = _detail;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(_loadFailed ? '加载失败' : '${meta?['session_name'] ?? '班会详情'}'),
        actions: [
          if (!_loadFailed && meta != null) ...[
            if (meta['isLocal'] == true)
              TextButton(
                onPressed: _busy ? null : _syncLocal,
                child: const Text('同步'),
              ),
            if (meta['isLocal'] != true) ...[
              IconButton(icon: const Icon(Icons.download), onPressed: _exportDetailCsv),
              IconButton(icon: const Icon(Icons.share), onPressed: _shareDetail),
            ],
          ],
        ],
      ),
      body: Stack(
        children: [
          if (_busy && detail == null && !_loadFailed)
            const Center(child: CircularProgressIndicator())
          else if (_loadFailed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_loadError ?? '加载失败', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          else if (detail != null)
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _detailSummaryHeader()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final r = detail[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _detailRecordCard(r, admin),
                        );
                      },
                      childCount: detail.length,
                    ),
                  ),
                ),
              ],
            ),
          if (_busy && detail != null) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _AttendancePiePainter extends CustomPainter {
  _AttendancePiePainter({required this.counts, required this.emptyRingColor});

  final Map<String, int> counts;
  final Color emptyRingColor;

  static const _green = Color(0xFF22C55E);
  static const _yellow = Color(0xFFEAB308);
  static const _blue = Color(0xFF3B82F6);
  static const _red = Color(0xFFEF4444);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final p = counts['present'] ?? 0;
    final l = counts['late'] ?? 0;
    final v = counts['leave'] ?? 0;
    final a = counts['absent'] ?? 0;
    final t = p + l + v + a;
    if (t == 0) {
      final paint = Paint()
        ..color = emptyRingColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
      return;
    }
    var start = -math.pi / 2;
    void drawSeg(int n, Color color) {
      if (n == 0) return;
      final sweep = 2 * math.pi * n / t;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, true, paint);
      start += sweep;
    }

    drawSeg(p, _green);
    drawSeg(l, _yellow);
    drawSeg(v, _blue);
    drawSeg(a, _red);
  }

  @override
  bool shouldRepaint(covariant _AttendancePiePainter oldDelegate) {
    return oldDelegate.counts['present'] != counts['present'] ||
        oldDelegate.counts['late'] != counts['late'] ||
        oldDelegate.counts['leave'] != counts['leave'] ||
        oldDelegate.counts['absent'] != counts['absent'] ||
        oldDelegate.emptyRingColor != emptyRingColor;
  }
}
