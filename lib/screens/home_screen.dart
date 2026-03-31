import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/audit_service.dart';
import '../services/easter_egg_audio_service.dart';
import '../state/app_controller.dart';
import '../state/root_modal_barrier.dart';
import '../theme/app_theme.dart';
import '../widgets/top_toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _hiddenTapCount = 0;
  DateTime _lastHiddenTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _easterTriggeredInBurst = false;
  bool _developerTriggeredInBurst = false;
  bool _playerDialogShowing = false;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了，注意休息 🌙';
    if (h < 9) return '早上好，元气满满 ☀️';
    if (h < 12) return '上午好，加油工作 ☕';
    if (h < 14) return '中午好，记得午休 🍱';
    if (h < 18) return '下午好，坚持一下 🚀';
    if (h < 22) return '晚上好，享受生活 🍷';
    return '深夜了，早点睡哦 🛌';
  }

  Future<void> _startSession(BuildContext context, AppController app) async {
    unawaited(AuditService.instance.logEvent(
      category: 'feature',
      action: 'tap_start_session',
      feature: 'home',
    ));
    if (app.students.isEmpty) {
      TopToast.show(context, '请先导入学生名单', error: true);
      unawaited(AuditService.instance.logEvent(
        category: 'feature',
        action: 'start_session_blocked_no_students',
        feature: 'session',
      ));
      return;
    }
    final name = await _showSessionNameDialog(context);
    if (name == null || !context.mounted) return;
    unawaited(AuditService.instance.logEvent(
      category: 'feature',
      action: 'start_session_confirmed',
      feature: 'session',
    ));
    app.beginDraftSession(name);
    context.push('/session');
  }

  Future<String?> _showSessionNameDialog(BuildContext context) {
    rootModalBarrierVisible.value = true;
    return showGeneralDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return const _SessionNameDialog();
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final fade = Tween<double>(begin: 0, end: 1).animate(curved);
        final scale = Tween<double>(begin: 0.96, end: 1.0).animate(curved);
        final slide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
    ).whenComplete(() {
      rootModalBarrierVisible.value = false;
    });
  }

  Future<void> _handleTitleTap(AppController app) async {
    final now = DateTime.now();
    if (now.difference(_lastHiddenTapAt) > const Duration(seconds: 2)) {
      _hiddenTapCount = 0;
      _easterTriggeredInBurst = false;
      _developerTriggeredInBurst = false;
    }
    _lastHiddenTapAt = now;
    _hiddenTapCount++;

    if (!_easterTriggeredInBurst && _hiddenTapCount >= 3) {
      _easterTriggeredInBurst = true;
      if (!_playerDialogShowing && context.mounted) {
        _playerDialogShowing = true;
        try {
          final localPath = await EasterEggAudioService.instance.getBestPlayablePath();
          if (!context.mounted) return;
          await showDialog<void>(
            context: context,
            builder: (_) => _EasterEggPlayerDialog(
              localPath: localPath,
              remoteUrl: AppConfig.easterEggAudioUrl,
            ),
          );
        } finally {
          _playerDialogShowing = false;
        }
      }
    }

    if (!_developerTriggeredInBurst && _hiddenTapCount >= 10) {
      _developerTriggeredInBurst = true;
      unawaited(app.setDebugMode(true));
      if (context.mounted) {
        TopToast.show(context, '已开启调试模式：底栏设置 → 开发者 可关闭');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final cs = Theme.of(context).colorScheme;
    final metaStyle = TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600);

    return Scaffold(
      body: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _handleTitleTap(app),
                            child: Text(
                              '签到助手',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 28,
                                  ),
                            ),
                          ),
                          Text('v${app.localVersionLabel}', style: metaStyle),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.duoGreen,
                      AppTheme.duoGreenDark,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.duoGreen.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1.3),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _heroStat(
                          icon: Icons.groups_rounded,
                          value: app.isHomeDataBootstrapping ? '…' : '${app.students.length}',
                          label: '名册人数',
                        ),
                        const SizedBox(width: 16),
                        _heroStat(
                          icon: Icons.sync_rounded,
                          value: app.isHomeDataBootstrapping ? '同步中' : '已就绪',
                          label: '服务状态',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text('核心操作', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  _actionButton(
                    context,
                    icon: Icons.play_arrow_rounded,
                    title: '开始新点名',
                    subtitle: '发起一次即时考勤',
                    color: AppTheme.duoGreen,
                    onTap: (app.busy || app.isHomeDataBootstrapping) ? null : () => _startSession(context, app),
                  ),
                  const SizedBox(height: 12),
                  _actionButton(
                    context,
                    icon: Icons.group_add_rounded,
                    title: '管理学生名册',
                    subtitle: '同步名册或手动编辑',
                    color: AppTheme.duoBlue,
                    onTap: () {
                      unawaited(AuditService.instance.logEvent(
                        category: 'feature',
                        action: 'tap_manage_students',
                        feature: 'home',
                      ));
                      context.push('/students/manage');
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.tips_and_updates_rounded, color: AppTheme.duoOrange, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '点名时支持拼音辅助与语音播报。可通过底栏快速切换至「统计」或「日志」。',
                          style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurface, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 120),
                child: Text('蒙ICP备2025031646号-1', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat({required IconData icon, required String value, required String label}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
                    Text(subtitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EasterEggPlayerDialog extends StatefulWidget {
  const _EasterEggPlayerDialog({
    required this.localPath,
    required this.remoteUrl,
  });

  final String? localPath;
  final String remoteUrl;

  @override
  State<_EasterEggPlayerDialog> createState() => _EasterEggPlayerDialogState();
}

class _EasterEggPlayerDialogState extends State<_EasterEggPlayerDialog> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  PlayerState _state = PlayerState.stopped;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_startPlayback());
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fromCache = widget.localPath != null;
    return AlertDialog(
      title: const Text('隐藏播放器'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('赵雷 - 我记得'),
          const SizedBox(height: 8),
          Text(
            fromCache ? '音频来源：本地缓存' : '音频来源：在线流',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_starting) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        IconButton(
          onPressed: _starting ? null : _playOrPause,
          icon: Icon(_state == PlayerState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          tooltip: _state == PlayerState.playing ? '暂停' : '播放',
        ),
        IconButton(
          onPressed: _starting ? null : _stop,
          icon: const Icon(Icons.stop_rounded),
          tooltip: '停止',
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _startPlayback() async {
    try {
      final player = await _ensurePlayer();
      if (player == null) {
        _error = '音频组件未就绪，请重启应用后再试';
        return;
      }
      await player.setReleaseMode(ReleaseMode.loop);
      if (widget.localPath != null) {
        await player.play(DeviceFileSource(widget.localPath!), volume: 0.75);
      } else if (widget.remoteUrl.trim().isNotEmpty) {
        await player.play(UrlSource(widget.remoteUrl.trim()), volume: 0.75);
      } else {
        throw Exception('未配置彩蛋音频地址');
      }
    } catch (_) {
      _error = '音频播放失败，请稍后重试';
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _playOrPause() async {
    final player = await _ensurePlayer();
    if (player == null) return;
    try {
      if (_state == PlayerState.playing) {
        await player.pause();
        return;
      }
      if (widget.localPath != null) {
        await player.play(DeviceFileSource(widget.localPath!), volume: 0.75);
      } else if (widget.remoteUrl.trim().isNotEmpty) {
        await player.play(UrlSource(widget.remoteUrl.trim()), volume: 0.75);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '音频播放失败，请稍后重试';
      });
    }
  }

  Future<void> _stop() async {
    final player = await _ensurePlayer();
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '停止播放失败，请稍后重试';
      });
    }
  }

  Future<AudioPlayer?> _ensurePlayer() async {
    if (_player != null) return _player;
    try {
      final player = AudioPlayer();
      _stateSub = player.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() => _state = s);
      });
      _player = player;
      return player;
    } on MissingPluginException catch (_) {
      if (!mounted) return null;
      setState(() {
        _error = '音频组件未安装，请重启后再试';
      });
      return null;
    } catch (_) {
      if (!mounted) return null;
      setState(() {
        _error = '音频初始化失败，请稍后重试';
      });
      return null;
    }
  }
}

class _SessionNameDialog extends StatefulWidget {
  const _SessionNameDialog();
  @override
  State<_SessionNameDialog> createState() => _SessionNameDialogState();
}

class _SessionNameDialogState extends State<_SessionNameDialog> {
  late final TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('这节课叫什么？'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '例如：第十二周 道法',
          filled: true,
          fillColor: cs.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.primary, width: 1.6),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('开始')),
      ],
    );
  }

  void _submit() {
    var n = _ctrl.text.trim();
    if (n.isEmpty) {
      final d = DateTime.now();
      n = '${d.month}月${d.day}日点名';
    }
    Navigator.pop(context, n);
  }
}
