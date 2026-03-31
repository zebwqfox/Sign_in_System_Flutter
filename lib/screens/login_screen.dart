import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pw = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final app = context.read<AppController>();
    try {
      await app.login(_pw.text);
      if (mounted) context.go('/');
    } catch (e) {
      final verbose = app.debugMode;
      setState(() => _error = verbose ? '$e' : '密码错误或无法连接服务器');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AppController>().busy;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Text(
                '系统登录',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pw,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '管理员密码',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(busy ? '验证中…' : '进入系统'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
