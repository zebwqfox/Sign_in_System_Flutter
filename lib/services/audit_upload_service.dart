import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'storage_service.dart';

class AuditUploadService {
  AuditUploadService._();
  static final AuditUploadService instance = AuditUploadService._();

  StorageService? _storage;
  bool _uploading = false;

  void init(StorageService storage) {
    _storage = storage;
  }

  Future<void> uploadOnStartupSilently() async {
    if (_uploading) return;
    final storage = _storage;
    if (storage == null) return;

    final endpoint = AppConfig.auditUploadUrl.trim();
    if (endpoint.isEmpty) return;

    _uploading = true;
    try {
      final all = storage.loadAuditEvents();
      if (all.isEmpty) return;

      final lastUploadedTs = storage.auditLastUploadedTsMs;
      final pending = all.where((e) {
        final ts = (e['ts_ms'] is num) ? (e['ts_ms'] as num).toInt() : 0;
        return ts > lastUploadedTs;
      }).toList();
      if (pending.isEmpty) return;

      const chunkSize = 200;
      final dio = Dio();
      var uploadedMaxTs = lastUploadedTs;
      for (var i = 0; i < pending.length; i += chunkSize) {
        final chunk = pending.sublist(i, (i + chunkSize > pending.length) ? pending.length : i + chunkSize);
        final headers = <String, dynamic>{};
        if (AppConfig.auditUploadToken.trim().isNotEmpty) {
          headers['x-audit-token'] = AppConfig.auditUploadToken.trim();
        }
        final resp = await dio.post(
          endpoint,
          data: {'events': chunk},
          options: Options(
            headers: headers,
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 12),
          ),
        );
        if (resp.statusCode == null || resp.statusCode! < 200 || resp.statusCode! >= 300) {
          return;
        }
        for (final e in chunk) {
          final ts = (e['ts_ms'] is num) ? (e['ts_ms'] as num).toInt() : 0;
          if (ts > uploadedMaxTs) uploadedMaxTs = ts;
        }
      }
      if (uploadedMaxTs > lastUploadedTs) {
        await storage.setAuditLastUploadedTsMs(uploadedMaxTs);
      }
    } catch (_) {
      // 静默上传：任何异常都忽略，不影响用户使用。
    } finally {
      _uploading = false;
    }
  }
}
