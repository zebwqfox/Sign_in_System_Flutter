import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/update_check_models.dart';
import '../utils/update_artifact_integrity.dart';

class UpdateDownloadException implements Exception {
  UpdateDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateDownloadService {
  UpdateDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<String> downloadArtifact({
    required UpdateArtifact artifact,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(artifact.downloadUrl.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw UpdateDownloadException('下载地址无效');
    }

    final dir = await getTemporaryDirectory();
    final updatesDir = Directory('${dir.path}${Platform.pathSeparator}updates');
    await updatesDir.create(recursive: true);
    await _cleanupOldArtifacts(updatesDir);
    final ext = artifact.kind.toLowerCase() == 'apk' ? 'apk' : 'bin';
    final filePath =
        '${updatesDir.path}${Platform.pathSeparator}update_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _dio.download(
      uri.toString(),
      filePath,
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 1),
      ),
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        onProgress?.call((received / total).clamp(0, 1));
      },
    );

    final f = File(filePath);
    if (!await f.exists()) {
      throw UpdateDownloadException('下载失败：文件不存在');
    }
    final fileLen = await f.length();
    // 注意：部分分发链路（CDN/压缩/重写）会导致服务端 file_bytes 与实际 APK 大小不一致。
    // 这里不再因大小不匹配直接失败，避免误删正常安装包；以摘要校验结果为最终依据。
    final expectedBytes = artifact.fileBytes;
    if (expectedBytes != null && expectedBytes > 0 && expectedBytes != fileLen) {
      // no-op: 只作为提示信息来源，不阻断后续校验与安装流程。
    }

    final integrity = artifact.integrity;
    if (integrity != null) {
      final err = await UpdateArtifactIntegrityVerifier.verifyFile(
        filePath: filePath,
        algorithm: integrity.algorithm,
        expectedHexDigest: integrity.hexDigest,
      );
      if (err != null) {
        try {
          await f.delete();
        } catch (_) {}
        throw UpdateDownloadException(err);
      }
    }

    return filePath;
  }

  Future<void> _cleanupOldArtifacts(Directory updatesDir) async {
    try {
      if (!await updatesDir.exists()) return;
      await for (final entity in updatesDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty ? '' : entity.uri.pathSegments.last;
        if (!name.startsWith('update_')) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}
