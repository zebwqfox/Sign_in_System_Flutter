import 'dart:io';

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

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  int _rate(List<AttendanceRecord> records) {
    if (records.isEmpty) return 0;
    final p = records.where((r) => r.status == 'present' || r.status == 'late').length;
    return ((p / records.length) * 100).round();
  }

  String _csv(List<AttendanceRecord> records, String sessionName) {
    final b = StringBuffer('\uFEFF学号,姓名,状态,备注\n');
    for (final r in records) {
      final sm = {
            'present': '出勤',
            'late': '迟到',
            'leave': '请假',
            'absent': '缺勤',
          }[r.status] ??
          '缺勤';
      b.write('${r.studentId},${r.studentName},$sm,${r.reason}\n');
    }
    return b.toString();
  }

  Future<void> _export(BuildContext context, AppController app) async {
    final text = _csv(app.completedRecords, app.completedSessionName);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${app.completedSessionName}_考勤.csv');
    await f.writeAsString(text);
    await Share.shareXFiles([XFile(f.path)], text: '考勤导出');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final name = app.completedSessionName;
    final records = app.completedRecords;
    final rate = _rate(records);
    final abnormal = records.where((r) => r.status != 'present').toList();
    final sid = app.completedSessionId;
    final local = app.completedIsLocal;
    final shareUrl = (sid != null && !local) ? '${AppConfig.shareBaseUrl}/share?share_id=$sid' : '';

    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('$rate%', textAlign: TextAlign.center, style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.green.shade700)),
          Text('出勤率', textAlign: TextAlign.center, style: TextStyle(color: Colors.green.shade800)),
          if (local) ...[
            const SizedBox(height: 16),
            Material(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('已保存到本地', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('请在网络恢复后到历史记录中同步到服务器。'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.go('/history'),
                      child: const Text('前往历史记录'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _export(context, app),
                  icon: const Icon(Icons.download),
                  label: const Text('导出 CSV'),
                ),
              ),
              if (shareUrl.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('分享摘要'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QrImageView(data: shareUrl, size: 200),
                              const SizedBox(height: 8),
                              SelectableText(shareUrl, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: shareUrl));
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制链接')));
                                }
                              },
                              child: const Text('复制链接'),
                            ),
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('分享'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Text('异常名单', style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          if (abnormal.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('全员全勤 🎉')))
          else
            ...abnormal.map((r) {
              return ListTile(
                title: Text(r.studentName),
                subtitle: Text(r.studentId),
                trailing: Chip(label: Text(r.reason.isEmpty ? r.status : r.reason)),
              );
            }),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.go('/'),
            child: const Text('完成并返回'),
          ),
        ],
      ),
    );
  }
}
