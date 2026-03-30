import 'package:flutter/material.dart';

import '../state/app_controller.dart';

/// 单行主题切换，避免 [SegmentedButton] 在中文下折成两列。
class ThemeModeBar extends StatelessWidget {
  const ThemeModeBar({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: _cell(context, cs, ThemeMode.system, Icons.brightness_auto_outlined, '系统', '跟随系统亮度')),
        const SizedBox(width: 8),
        Expanded(child: _cell(context, cs, ThemeMode.light, Icons.light_mode_outlined, '浅色', '始终浅色')),
        const SizedBox(width: 8),
        Expanded(child: _cell(context, cs, ThemeMode.dark, Icons.dark_mode_outlined, '深色', '始终深色')),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    ColorScheme cs,
    ThemeMode mode,
    IconData icon,
    String label,
    String tooltip,
  ) {
    final sel = app.themeMode == mode;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: sel ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => app.setThemeMode(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
