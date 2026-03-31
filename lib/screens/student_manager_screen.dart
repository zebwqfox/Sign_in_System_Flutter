import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/top_toast.dart';

class StudentManagerScreen extends StatefulWidget {
  const StudentManagerScreen({super.key});

  @override
  State<StudentManagerScreen> createState() => _StudentManagerScreenState();
}

class _StudentManagerScreenState extends State<StudentManagerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _importCtrl = TextEditingController();
  bool _selectMode = false;
  final _selected = <int>{};
  bool _busy = false;

  @override
  void dispose() {
    _tabs.dispose();
    _importCtrl.dispose();
    super.dispose();
  }

  Future<void> _import(AppController app) async {
    final lines = _importCtrl.text.split('\n');
    final list = <Map<String, dynamic>>[];
    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final p1 = parts[0];
      final p2 = parts[1];
      final idNum = RegExp(r'\d').hasMatch(p1) && !RegExp(r'\d').hasMatch(p2);
      list.add(idNum ? {'student_id': p1, 'name': p2} : {'student_id': p2, 'name': p1});
    }
    if (list.isEmpty) {
      _toast(context, '格式不正确，无法识别', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await app.api.importStudents(list);
      _importCtrl.clear();
      await app.refreshStudents();
      if (mounted) _toast(context, '成功导入 ${list.length} 人');
      _tabs.animateTo(0);
    } catch (e) {
      if (mounted) _toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBatch(AppController app) async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('即将删除 ${_selected.length} 名学生，不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.duoRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await app.api.batchDeleteStudents(_selected.toList());
      _selected.clear();
      _selectMode = false;
      await app.refreshStudents();
      if (mounted) _toast(context, '已删除');
    } catch (e) {
      if (mounted) _toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(BuildContext ctx, String msg, {bool error = false}) {
    TopToast.show(ctx, msg, error: error);
  }

  Future<void> _editStudent(AppController app, Student s) async {
    final nameCtrl = TextEditingController(text: s.name);
    final idCtrl = TextEditingController(text: s.studentId);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('编辑学生'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名')),
              const SizedBox(height: 8),
              TextField(controller: idCtrl, decoration: const InputDecoration(labelText: '学号')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final del = await showDialog<bool>(
                  context: ctx,
                  builder: (c2) => AlertDialog(
                    title: const Text('删除'),
                    content: Text('确定删除 ${s.name}？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.duoRed),
                        onPressed: () => Navigator.pop(c2, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (del != true || !ctx.mounted) return;
                try {
                  await app.api.deleteStudent(s.id);
                  await app.refreshStudents();
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, false);
                  if (mounted) _toast(context, '已删除');
                } catch (e) {
                  if (mounted) _toast(context, '$e', error: true);
                }
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      );
      if (ok != true) return;
      final name = nameCtrl.text.trim();
      final sid = idCtrl.text.trim();
      if (name.isEmpty || sid.isEmpty) return;
      setState(() => _busy = true);
      try {
        await app.api.updateStudent(s.id, name, sid);
        await app.refreshStudents();
        if (mounted) _toast(context, '保存成功');
      } catch (e) {
        if (mounted) _toast(context, '$e', error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        idCtrl.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final students = app.students;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('学生名册管理')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded, color: AppTheme.duoBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '当前共 ${students.length} 名学生',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: const EdgeInsets.all(4),
                    indicator: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: '成员列表'),
                      Tab(text: '批量导入'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _buildMembersTab(context, app, students, cs),
                    _buildImportTab(context, app, cs),
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMembersTab(
    BuildContext context,
    AppController app,
    List<Student> students,
    ColorScheme cs,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text('已选 ${_selected.length}', style: TextStyle(color: cs.onSurfaceVariant)),
              const Spacer(),
              if (!_selectMode)
                TextButton(
                  onPressed: () => setState(() => _selectMode = true),
                  child: const Text('批量管理'),
                )
              else ...[
                TextButton(
                  onPressed: () => setState(() {
                    _selectMode = false;
                    _selected.clear();
                  }),
                  child: const Text('完成'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == students.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(students.map((e) => e.id));
                      }
                    });
                  },
                  child: Text(_selected.length == students.length ? '全不选' : '全选'),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : () => _deleteBatch(app),
                    child: Text('删除(${_selected.length})', style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: students.isEmpty
              ? Center(
                  child: Text(
                    '暂无学生数据',
                    style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: students.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final s = students[i];
                    final on = _selected.contains(s.id);
                    return Material(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _selectMode
                            ? () => setState(() {
                                  if (on) {
                                    _selected.remove(s.id);
                                  } else {
                                    _selected.add(s.id);
                                  }
                                })
                            : null,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          leading: _selectMode
                              ? Icon(
                                  on ? Icons.check_circle : Icons.circle_outlined,
                                  color: on ? cs.primary : cs.outline,
                                )
                              : CircleAvatar(
                                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                                  child: Text(
                                    s.name.isNotEmpty ? s.name.substring(0, 1) : '?',
                                    style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
                                  ),
                                ),
                          title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('学号：${s.studentId}'),
                          trailing: _selectMode
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.edit_rounded),
                                  onPressed: () => _editStudent(app, s),
                                ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildImportTab(BuildContext context, AppController app, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '每行两列，学号和姓名，支持空格或 Tab 分隔。\n示例：2021001 张三',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.45),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: _importCtrl,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '2021001 张三\n2021002 李四',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _import(app),
            icon: const Icon(Icons.upload_rounded),
            label: const Text('确认导入'),
          ),
        ],
      ),
    );
  }
}
