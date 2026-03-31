import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

class HistoryRecordEditScreen extends StatefulWidget {
  const HistoryRecordEditScreen({
    super.key,
    required this.sessionId,
    required this.recordId,
  });

  final String sessionId;
  final String recordId;

  @override
  State<HistoryRecordEditScreen> createState() => _HistoryRecordEditScreenState();
}

class _HistoryRecordEditScreenState extends State<HistoryRecordEditScreen> {
  bool _busy = false;
  bool _loading = true;
  String? _loadError;

  Map<String, dynamic>? _sessionMeta;
  AttendanceRecord? _record;

  late final TextEditingController _reasonCtrl;
  String _status = 'present';

  @override
  void initState() {
    super.initState();
    _reasonCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final app = context.read<AppController>();
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final sid = widget.sessionId;
      final rid = int.tryParse(widget.recordId);
      if (rid == null) throw 'recordId 无效';

      if (sid.startsWith('local_')) {
        final all = await app.storage.loadPendingSessions();
        final session = all.firstWhere((e) => e.id == sid);
        final rec = session.records.firstWhere((e) => e.id == rid);

        _sessionMeta = {
          'id': session.id,
          'session_name': session.sessionName,
          'created_at': session.createdAt,
          'total_students': session.totalStudents,
          'attendance_rate': session.attendanceRate,
          'isLocal': true,
        };
        _record = rec;
      } else {
        final sidNum = int.tryParse(sid);
        if (sidNum == null) throw 'sessionId 无效';

        final detail = await app.api.fetchSessionDetail(sidNum);
        _sessionMeta = detail.session;

        final recs = detail.records;
        final rec = recs.firstWhere((e) => e.id == rid);
        _record = rec;
      }
    } catch (e) {
      _loadError = '$e';
    } finally {
      final rec = _record;
      if (mounted) {
        _reasonCtrl.text = rec?.reason.trim() ?? '';
        _status = rec?.status ?? 'present';
        _loading = false;
      }
    }
  }

  Future<void> _pickStatus(String status) async {
    setState(() => _status = status);
    // Web：如果备注为空/默认文案，切换状态时自动补上默认原因（出勤则留空）
    final cur = _reasonCtrl.text.trim();
    if (cur.isEmpty) {
      if (status == 'present') {
        _reasonCtrl.text = '';
      } else {
        _reasonCtrl.text = _statusLabel(status);
      }
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return '';
      case 'late':
        return '迟到';
      case 'leave':
        return '请假';
      case 'absent':
      default:
        return '缺勤';
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final meta = _sessionMeta;
    final target = _record;
    if (meta == null || target == null) return;

    final status = _status;
    final reason = _reasonCtrl.text.trim();

    setState(() => _busy = true);
    try {
      final app = context.read<AppController>();

      if (meta['isLocal'] == true) {
        // 修改本地 pending_sessions
        final all = await app.storage.loadPendingSessions();
        final idx = all.indexWhere((s) => s.id == meta['id']);
        if (idx < 0) return;
        final session = all[idx];

        final recId = target.id;
        if (recId == null) return;
        final recIdx = session.records.indexWhere((r) => r.id == recId);
        if (recIdx < 0) return;

        session.records[recIdx] = AttendanceRecord(
          id: recId,
          studentId: session.records[recIdx].studentId,
          studentName: session.records[recIdx].studentName,
          status: status,
          reason: reason,
        );

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
      } else {
        final recId = target.id;
        if (recId == null) return;
        await app.api.updateRecord(recordId: recId, status: status, reason: reason);
      }

      if (mounted) context.pop(true);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _opt({
    required String status,
    required Color color,
    required String label,
    required IconData icon,
  }) {
    final isOn = _status == status;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: isOn ? 1 : 0.10),
        foregroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: isOn ? 0.65 : 0.40), width: 2),
        ),
      ),
      onPressed: _busy ? null : () => _pickStatus(status),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (isOn) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_rounded, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = _sessionMeta;
    final rec = _record;

    final title = meta?['session_name'] ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('修正考勤'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Text(_loadError!))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (title.isNotEmpty)
                          Text(
                            title,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: cs.onSurfaceVariant),
                          ),
                        const SizedBox(height: 10),
                        if (rec != null)
                          Text(
                            '${rec.studentName} (${rec.studentId})',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
                          ),
                        const SizedBox(height: 14),
                        GridView.count(
                          shrinkWrap: true,
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.15,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _opt(status: 'present', color: AppTheme.duoGreen, label: '出勤', icon: Icons.check_circle_rounded),
                            _opt(status: 'late', color: AppTheme.duoYellow, label: '迟到', icon: Icons.warning_rounded),
                            _opt(status: 'leave', color: AppTheme.duoBlue, label: '请假', icon: Icons.note_rounded),
                            _opt(status: 'absent', color: AppTheme.duoRed, label: '缺勤', icon: Icons.cancel_rounded),
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          maxLines: 1,
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
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('确认修改'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy ? null : () => context.pop(false),
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

