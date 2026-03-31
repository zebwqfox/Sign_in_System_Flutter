import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

class EasterEggAudioService {
  EasterEggAudioService._();
  static final EasterEggAudioService instance = EasterEggAudioService._();

  Future<String?>? _prefetchTask;

  String get remoteUrl => AppConfig.easterEggAudioUrl;

  Future<String?> prefetchSilently() {
    if (_prefetchTask != null) return _prefetchTask!;
    _prefetchTask = _doPrefetch().whenComplete(() => _prefetchTask = null);
    return _prefetchTask!;
  }

  Future<String?> getBestPlayablePath() async {
    final local = await _existingLocalPath();
    if (local != null) return local;
    return prefetchSilently();
  }

  Future<String?> _doPrefetch() async {
    final url = remoteUrl.trim();
    if (url.isEmpty) return null;

    try {
      final file = await _targetFile();
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) return file.path;
      }

      final dio = Dio();
      await dio.download(
        url,
        file.path,
        options: Options(
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 25),
        ),
        deleteOnError: true,
      );
      final len = await file.length();
      if (len <= 0) return null;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _existingLocalPath() async {
    try {
      final file = await _targetFile();
      if (!await file.exists()) return null;
      final len = await file.length();
      return len > 0 ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<File> _targetFile() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}${AppConfig.easterEggAudioFileName}');
  }
}
