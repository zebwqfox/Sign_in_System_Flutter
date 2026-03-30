import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../utils/deferred_work.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<LogEntry> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    scheduleAfterTransition(() {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    setState(() => _loading = true);
    try {
      _logs = await app.api.fetchLogs();
    } catch (_) {
      _logs = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: const Text('系统日志'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _logs.length,
              itemBuilder: (ctx, i) {
                final l = _logs[i];
                return Card(
                  child: ListTile(
                    title: Text(l.action, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${l.ip}\n${l.createdAt}'),
                    isThreeLine: true,
                    trailing: Chip(label: Text(l.location)),
                  ),
                );
              },
            ),
    );
  }
}
