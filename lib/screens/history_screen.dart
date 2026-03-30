import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../utils/deferred_work.dart';

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

/// 历史班会列表（详情见 [HistoryDetailScreen] 独立路由）。
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('获取历史失败，仅显示本地记录'),
              backgroundColor: Colors.orange,
            ),
          );
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同步成功')));
      await _refreshList();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失败：$e')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
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
          ListView.builder(
            padding: const EdgeInsets.all(12),
            physics: const BouncingScrollPhysics(),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final it = _items[i];
              final pct = (it.rate * 100).round();
              return Card(
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(child: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                      if (it.isLocal)
                        Chip(
                          label: const Text('未同步'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppTheme.duoOrange.withValues(alpha: 0.2),
                          labelStyle: const TextStyle(color: Color(0xFFC2410C), fontWeight: FontWeight.w800, fontSize: 11),
                        ),
                      Chip(
                        label: Text('$pct%'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: pct >= 90
                            ? AppTheme.duoGreen.withValues(alpha: 0.2)
                            : pct >= 60
                                ? AppTheme.duoYellow.withValues(alpha: 0.25)
                                : AppTheme.duoRed.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: pct >= 90
                              ? AppTheme.duoGreenDark
                              : pct >= 60
                                  ? const Color(0xFFA16207)
                                  : AppTheme.duoRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${it.createdAt} · ${it.total} 人',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  onTap: () => _openDetail(it.id),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.isLocal)
                        FilledButton(
                          onPressed: _busy || it.local == null ? null : () => _syncLocal(it.local!),
                          child: const Text('同步'),
                        ),
                      if (_editListMode && !it.isLocal)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            if (!mounted) return;
                            final ok = await _confirmDeleteHistory(it.title, isServer: true);
                            if (ok && mounted) await _deleteServer(it.id);
                          },
                        ),
                      if (_editListMode && it.isLocal)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            if (!mounted) return;
                            final app = context.read<AppController>();
                            final ok = await _confirmDeleteHistory(it.title, isServer: false);
                            if (ok && mounted) {
                              await app.storage.removePendingById(it.id);
                              await _refreshList();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

/// 第二步：倒计时结束后才可点「确认删除」。
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
