import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../utils/deferred_work.dart';
import '../widgets/top_toast.dart';

class _HistItem {
  _HistItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.total,
    required this.rate,
    required this.isLocal,
    this.local,
  });

  final String id;
  final String title;
  final String createdAt;
  final int total;
  final double rate;
  final bool isLocal;
  final LocalPendingSession? local;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<_HistItem> _items = [];
  bool _busy = false;
  bool _editListMode = false;

  @override
  void initState() {
    super.initState();
    scheduleAfterTransition(_refreshListIfMounted);
  }

  Future<void> _refreshListIfMounted() async {
    if (!mounted) return;
    await _refreshList();
  }

  Future<void> _refreshList() async {
    final app = context.read<AppController>();
    setState(() => _busy = true);
    try {
      final local = await app.storage.loadPendingSessions();
      var server = <SessionRow>[];
      try {
        server = await app.api.fetchHistorySessions();
      } catch (_) {
        if (mounted) {
          TopToast.show(context, '获取历史失败，仅显示本地记录', error: true);
        }
      }
      final merged = <_HistItem>[
        ...local.map(
          (e) => _HistItem(
            id: e.id,
            title: e.sessionName,
            createdAt: e.createdAt,
            total: e.totalStudents,
            rate: e.attendanceRate,
            isLocal: true,
            local: e,
          ),
        ),
        ...server.map(
          (e) => _HistItem(
            id: e.id,
            title: e.sessionName,
            createdAt: e.createdAt,
            total: e.totalStudents,
            rate: e.attendanceRate,
            isLocal: false,
          ),
        ),
      ]..sort((a, b) {
          final ta = DateTime.tryParse(a.createdAt)?.millisecondsSinceEpoch ?? 0;
          final tb = DateTime.tryParse(b.createdAt)?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
      setState(() => _items = merged);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDetail(String id) async {
    await context.push('/history/detail/${Uri.encodeComponent(id)}');
    if (mounted) _refreshList();
  }

  Future<void> _syncLocal(LocalPendingSession s) async {
    final app = context.read<AppController>();
    setState(() => _busy = true);
    try {
      await app.api.submitSession(sessionName: s.sessionName, records: s.records, createdAtIso: s.createdAt);
      await app.storage.removePendingById(s.id);
      if (mounted) TopToast.show(context, '同步成功');
      await _refreshList();
    } catch (e) {
      if (mounted) TopToast.show(context, '同步失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDeleteHistory(String title, {required bool isServer}) async {
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isServer ? '删除云端记录' : '删除本地记录'),
        content: Text('即将删除「$title」，此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return false;

    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HistoryDeleteCountdownDialog(title: title),
    );
    return step2 == true;
  }

  Future<void> _deleteServer(String id) async {
    final sid = int.tryParse(id);
    if (sid == null) return;
    final app = context.read<AppController>();
    setState(() => _busy = true);
    try {
      await app.api.deleteSession(sid);
      await _refreshList();
      if (mounted) TopToast.show(context, '已删除');
    } catch (e) {
      if (mounted) TopToast.show(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSessionName(String id, String initialName) async {
    final sid = int.tryParse(id);
    if (sid == null) return;
    final app = context.read<AppController>();
    final ctrl = TextEditingController(text: initialName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑会话名称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入会话名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await app.api.updateSessionName(sid, name);
      if (mounted) {
        TopToast.show(context, '会话名称已更新');
        await _refreshList();
      }
    } catch (e) {
      if (mounted) TopToast.show(context, '更新失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('历史记录'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _editListMode = !_editListMode),
            child: Text(_editListMode ? '完成' : '编辑'),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshList,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              itemCount: _items.length,
              itemBuilder: (ctx, i) {
                final it = _items[i];
                final cs = Theme.of(ctx).colorScheme;
                final pct = (it.rate * 100).round().clamp(0, 100);

                final borderColor = it.isLocal
                    ? AppTheme.duoOrange.withValues(alpha: 0.30)
                    : cs.outlineVariant.withValues(alpha: 0.55);
                final canOpen = !_editListMode && !it.isLocal;

                return InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: canOpen ? () => _openDetail(it.id) : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          // 让阴影只向下展开，避免顶部出现“盖在卡片上”的灰边。
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          spreadRadius: -8,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          it.title,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (it.isLocal)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppTheme.duoOrange.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: const Text(
                                            '未同步',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFC2410C)),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.duoGreen.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: AppTheme.duoGreen.withValues(alpha: 0.16)),
                                        ),
                                        child: Text(
                                          '$pct%',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.duoGreenDark),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '${it.createdAt} · ${it.total} 人',
                                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // trailing actions（Web：本地同步按钮 + 编辑模式下的删除/改名）
                            if (it.isLocal)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton(
                                    onPressed: _busy || it.local == null ? null : () => _syncLocal(it.local!),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.duoBlue.withValues(alpha: 0.92),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Text('同步', style: TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                  if (_editListMode)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                      onPressed: () async {
                                        if (!mounted) return;
                                        final app = context.read<AppController>();
                                        final ok = await _confirmDeleteHistory(it.title, isServer: false);
                                        if (!mounted || ok != true) return;
                                        await app.storage.removePendingById(it.id);
                                        await _refreshList();
                                      },
                                    ),
                                ],
                              )
                            else if (_editListMode)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: AppTheme.duoBlue),
                                    tooltip: '编辑会话名称',
                                    onPressed: () => _editSessionName(it.id, it.title),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                    onPressed: () async {
                                      if (!mounted) return;
                                      final ok = await _confirmDeleteHistory(it.title, isServer: true);
                                      if (!mounted || ok != true) return;
                                      await _deleteServer(it.id);
                                    },
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
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _HistoryDeleteCountdownDialog extends StatefulWidget {
  const _HistoryDeleteCountdownDialog({required this.title});
  final String title;
  @override
  State<_HistoryDeleteCountdownDialog> createState() => _HistoryDeleteCountdownDialogState();
}

class _HistoryDeleteCountdownDialogState extends State<_HistoryDeleteCountdownDialog> {
  static const _total = 3;
  int _left = _total;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_left <= 1) {
          _left = 0;
          _timer?.cancel();
          _timer = null;
        } else {
          _left--;
        }
      });
    });
  }
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final canConfirm = _left == 0;
    return AlertDialog(
      title: const Text('最后确认'),
      content: Text(
        canConfirm
            ? '确定永久删除「${widget.title}」？'
            : '请再次确认删除「${widget.title}」。\n\n$_left 秒后可点击「确认删除」。',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: canConfirm ? () => Navigator.pop(context, true) : null,
          child: Text(canConfirm ? '确认删除' : '确认删除（${_left}s）'),
        ),
      ],
    );
  }
}
