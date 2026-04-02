import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BottomFunctionBar extends StatefulWidget {
  const BottomFunctionBar({
    super.key,
    required this.light,
    required this.router,
  });

  final bool light;
  final GoRouter router;

  @override
  State<BottomFunctionBar> createState() => _BottomFunctionBarState();
}

class _BottomFunctionBarState extends State<BottomFunctionBar> {
  bool _ready = false;
  String _location = '/';
  bool _visible = true;

  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _location = _currentLocation();
    _visible = _shouldShowForLocation(_location);
    _listener = () {
      if (!_ready) return;
      if (!mounted) return;
      final newLoc = _currentLocation();
      final show = _shouldShowForLocation(newLoc);
      setState(() {
        _location = newLoc;
        _visible = show;
      });
    };

    // 延迟到首帧后再开始 setState，避免 GoRouter 初始化阶段的构建期冲突
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ready = true;
      final newLoc = _currentLocation();
      final show = _shouldShowForLocation(newLoc);
      setState(() {
        _location = newLoc;
        _visible = show;
      });
    });

    widget.router.routerDelegate.addListener(_listener);
  }

  @override
  void didUpdateWidget(covariant BottomFunctionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_listener);
      widget.router.routerDelegate.addListener(_listener);
      _location = _currentLocation();
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_listener);
    super.dispose();
  }

  String _currentLocation() {
    try {
      final conf = widget.router.routerDelegate.currentConfiguration;
      if (conf.isEmpty) return '/login';
      return conf.last.matchedLocation;
    } catch (_) {
      return '/';
    }
  }

  bool _shouldShowForLocation(String loc) {
    // 只在“主功能页”常驻，二级页面（详情、编辑等）全部隐藏
    return loc == '/' || loc == '/history' || loc == '/stats' || loc == '/logs' || loc == '/settings';
  }

  int get _tabIndex {
    if (_location == '/') return 0;
    if (_location == '/history') return 1;
    if (_location == '/stats') return 2;
    if (_location == '/logs') return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeColor = scheme.primary;
    final inactiveColor = scheme.onSurfaceVariant;

    final barWidget = Container(
      height: 64,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _tab(context, 0, Icons.home_rounded, '首页', '/', _tabIndex == 0, activeColor, inactiveColor),
            _tab(context, 1, Icons.history_rounded, '历史', '/history', _tabIndex == 1, activeColor, inactiveColor),
            _tab(context, 2, Icons.bar_chart_rounded, '统计', '/stats', _tabIndex == 2, activeColor, inactiveColor),
            _tab(context, 3, Icons.receipt_long_rounded, '日志', '/logs', _tabIndex == 3, activeColor, inactiveColor),
            _tab(context, 4, Icons.settings_rounded, '设置', '/settings', _tabIndex == 4, activeColor, inactiveColor),
          ],
        ),
      ),
    );

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOutCubic,
        height: _visible ? 64 : 0,
        child: ClipRect(
          child: IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _visible ? 1 : 0,
              child: Transform.translate(
                offset: _visible ? Offset.zero : const Offset(0, 18),
                child: barWidget,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    int index,
    IconData icon,
    String label,
    String target,
    bool active,
    Color activeColor,
    Color inactiveColor,
  ) {
    final color = active ? activeColor : inactiveColor;
    final outlinedIcon = _outlinedVariant(icon);
    return Expanded(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          onTap: () => widget.router.go(target),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: active
                      ? TweenAnimationBuilder<double>(
                          key: ValueKey<String>('draw-$index-$active'),
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          builder: (context, progress, _) {
                            final revealStart = (progress - 0.22).clamp(0.0, 1.0);
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (bounds) {
                                    final edge = progress.clamp(0.0, 1.0);
                                    final soft = 0.18;
                                    final hardStart = (edge - soft).clamp(0.0, 1.0);
                                    return LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: const [
                                        Colors.black,
                                        Colors.black,
                                        Colors.transparent,
                                        Colors.transparent,
                                      ],
                                      stops: [
                                        0,
                                        hardStart,
                                        edge,
                                        1,
                                      ],
                                    ).createShader(bounds);
                                  },
                                  child: Icon(outlinedIcon, size: 24, color: activeColor),
                                ),
                                Opacity(
                                  opacity: revealStart,
                                  child: Icon(icon, size: 24, color: activeColor),
                                ),
                              ],
                            );
                          },
                        )
                      : Icon(outlinedIcon, size: 24, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _outlinedVariant(IconData icon) {
    if (icon == Icons.home_rounded) return Icons.home_outlined;
    if (icon == Icons.history_rounded) return Icons.history_outlined;
    if (icon == Icons.bar_chart_rounded) return Icons.bar_chart_outlined;
    if (icon == Icons.receipt_long_rounded) return Icons.receipt_long_outlined;
    if (icon == Icons.settings_rounded) return Icons.settings_outlined;
    return icon;
  }
}
