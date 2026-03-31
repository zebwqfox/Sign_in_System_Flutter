import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_controller.dart';
import '../widgets/top_toast.dart';

/// 与 Web `StudentManager.vue` 对齐：列表 / 导入 / 编辑 / 批量删除。
Future<void> showStudentManagerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _StudentManagerBody(),
  );
}

class _StudentManagerBody extends StatefulWidget {
  const _StudentManagerBody();

  @override
  State<_StudentManagerBody> createState() => _StudentManagerBodyState();
}

class _StudentManagerBodyState extends State<_StudentManagerBody> with SingleTickerProviderStateMixin {
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
      if (parts.length >= 2) {
        final p1 = parts[0], p2 = parts[1];
        final idNum = RegExp(r'\d').hasMatch(p1) && !RegExp(r'\d').hasMatch(p2);
        list.add(idNum ? {'student_id': p1, 'name': p2} : {'student_id': p2, 'name': p1});
      }
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
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
                    content: Text('确定删除 ${s.name} ？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (del == true && ctx.mounted) {
                  try {
                    await app.api.deleteStudent(s.id);
                    await app.refreshStudents();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx, false);
                    if (!mounted) return;
                    _toast(context, '已删除');
                  } catch (e) {
                    if (!mounted) return;
                    _toast(context, '$e', error: true);
                  }
                }
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('关闭')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
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
      // 等路由从树上卸下后再 dispose，避免编辑框 teardown 时仍绑定已释放的 Controller
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
    final h = MediaQuery.of(context).size.height * 0.88;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: h,
      child: Stack(
        children: [
          Column(
            children: [
              TabBar(
                controller: _tabs,
                tabs: const [Tab(text: '成员列表'), Tab(text: '批量导入')],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Text('共 ${students.length} 人', style: TextStyle(color: cs.onSurfaceVariant)),
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
                              ? const Center(child: Text('暂无数据'))
                              : ListView.builder(
                                  itemCount: students.length,
                                  itemBuilder: (ctx, i) {
                                    final s = students[i];
                                    final on = _selected.contains(s.id);
                                    return ListTile(
                                      leading: _selectMode
                                          ? Icon(on ? Icons.check_circle : Icons.circle_outlined,
                                              color: on ? cs.primary : cs.outline)
                                          : null,
                                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text(s.studentId),
                                      trailing: _selectMode
                                          ? null
                                          : IconButton(icon: const Icon(Icons.edit), onPressed: () => _editStudent(app, s)),
                                      onTap: _selectMode
                                          ? () => setState(() {
                                                if (on) {
                                                  _selected.remove(s.id);
                                                } else {
                                                  _selected.add(s.id);
                                                }
                                              })
                                          : null,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('粘贴两列：学号 姓名', style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: TextField(
                              controller: _importCtrl,
                              maxLines: null,
                              expands: true,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: '2021001  张三',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _busy ? null : () => _import(app),
                            child: const Text('确认导入'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF), child: Center(child: CircularProgressIndicator()))),
        ],
      ),
    );
  }
}
