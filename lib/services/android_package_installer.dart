import 'dart:io';

import 'package:flutter/services.dart';

class AndroidPackageInstaller {
  AndroidPackageInstaller._();

  static const MethodChannel _channel = MethodChannel('sign.update/install');

  static bool get isSupported => Platform.isAndroid;

  static Future<bool> canRequestPackageInstalls() async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
    return ok ?? false;
  }

  static Future<void> openUnknownSourcesSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openUnknownSourcesSettings');
  }

  static Future<bool> installApk(String filePath) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
    return ok ?? false;
  }
}
