import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _hapticChannel = MethodChannel('com.your_app/haptics');

bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// iOS：优先 `AppDelegate` 内 UISelection / UIImpact / UINotification 原生触感。
/// Android 等：`HapticFeedback`。
class Haptics {
  static Future<void> _iosOrFlutter(
    String iosMethod,
    void Function() flutterFallback,
  ) async {
    if (kIsWeb) return;
    if (_ios) {
      try {
        await _hapticChannel.invokeMethod<void>(iosMethod);
      } catch (_) {
        flutterFallback();
      }
      return;
    }
    flutterFallback();
  }

  /// 极轻微（列表、开关）
  static Future<void> selection() => _iosOrFlutter(
        'selection',
        HapticFeedback.selectionClick,
      );

  /// 沉重撞击（主按钮等）
  static Future<void> rigid() => _iosOrFlutter(
        'rigid',
        HapticFeedback.heavyImpact,
      );

  /// 成功
  static Future<void> success() => _iosOrFlutter(
        'success',
        HapticFeedback.mediumImpact,
      );

  /// 错误
  static Future<void> error() => _iosOrFlutter(
        'error',
        HapticFeedback.heavyImpact,
      );
}

Future<void> _pulseFlutter(int ms) async {
  if (kIsWeb) return;
  if (ms <= 14) {
    HapticFeedback.selectionClick();
  } else if (ms <= 30) {
    HapticFeedback.lightImpact();
  } else if (ms <= 45) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.heavyImpact();
  }
}

Future<void> _pulseIosNative(int ms) async {
  try {
    final method = ms <= 18 ? 'selection' : 'rigid';
    await _hapticChannel.invokeMethod<void>(method);
  } catch (_) {
    await _pulseFlutter(ms);
  }
}

/// 通用短触感：iOS 走原生 channel，Android 用时长映射到 `HapticFeedback`。
Future<void> pulse({int ms = 25}) async {
  if (kIsWeb) return;
  if (_ios) {
    await _pulseIosNative(ms);
  } else {
    await _pulseFlutter(ms);
  }
}

/// 与历史调用兼容。
Future<void> shortPulse({int ms = 25}) => pulse(ms: ms);
