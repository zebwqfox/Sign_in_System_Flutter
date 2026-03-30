import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import '../config/app_config.dart';
import '../models/update_check_models.dart';

/// 调用独立更新检查 URL（默认 `https://imm2.top/updatecheckfox`），与主业务 [ApiService] 隔离（无登录 Cookie）。
class UpdateCheckService {
  UpdateCheckService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
                /// 不可使用「<500」：301/302 等会被当成成功，正文常为 HTML，jsonDecode 失败。
                validateStatus: (s) =>
                    s != null && ((s >= 200 && s < 300) || (s >= 400 && s < 500)),
              ),
            );

  final Dio _dio;

  /// 仅 2xx 与 4xx（可带 JSON 错误体）；拒绝 3xx，便于手动按 Location 用 POST 重试。
  static bool _okStatus(int? s) =>
      s != null && ((s >= 200 && s < 300) || (s >= 400 && s < 500));

  static String get _platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'other';
    }
  }

  /// POST JSON，解析 [UpdateCheckResponse] 并计算 [UpdateCheckClientDecision]。
  Future<UpdateCheckClientDecision> checkForUpdates() async {
    final info = await PackageInfo.fromPlatform();
    final curBuild = int.tryParse(info.buildNumber) ?? 0;
    final Version currentVersion;
    try {
      currentVersion = Version.parse(info.version);
    } on FormatException {
      throw UpdateCheckException('无效的本地版本号: ${info.version}');
    }

    final req = UpdateCheckRequest(
      schemaVersion: 1,
      appChannel: AppConfig.updateCheckAppChannel,
      platform: _platformLabel,
      currentSemanticVersion: info.version,
      currentBuildNumber: curBuild,
      osVersion: _readOsVersion(),
    );

    Future<Response<dynamic>> postPlain(String url) {
      return _dio.post<dynamic>(
        url.trim(),
        data: req.toJson(),
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.jsonContentType,
          followRedirects: true,
          maxRedirects: 10,
          validateStatus: (s) => _okStatus(s),
        ),
      );
    }

    final baseUrl = AppConfig.updateCheckUrl.trim();
    late final Response<dynamic> res;
    try {
      res = await postPlain(baseUrl);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final loc = e.response?.headers.value('location') ?? e.response?.headers.value('Location');
      if ((code == 301 || code == 302 || code == 303 || code == 307 || code == 308) &&
          loc != null &&
          loc.trim().isNotEmpty) {
        final next = Uri.parse(baseUrl).resolve(loc.trim()).toString();
        try {
          res = await postPlain(next);
        } on DioException catch (e2) {
          throw UpdateCheckException(_dioErrorDetail(e2), statusCode: e2.response?.statusCode);
        }
      } else {
        throw UpdateCheckException(_dioErrorDetail(e), statusCode: e.response?.statusCode);
      }
    }

    final Map<String, dynamic> data;
    try {
      data = _parseResponseBodyAsJsonMap(res.data, statusCode: res.statusCode);
    } on FormatException catch (e) {
      throw UpdateCheckException('响应不是合法 JSON：${e.message}', statusCode: res.statusCode);
    }

    final parsed = UpdateCheckResponse.fromJson(data);
    if (!parsed.success) {
      throw UpdateCheckException(parsed.errorMessage ?? '检查失败', code: parsed.errorCode, response: parsed);
    }

    return _decide(parsed, currentVersion, curBuild);
  }

  String? _readOsVersion() => 'platform:${defaultTargetPlatform.name}';

  static String _dioErrorDetail(DioException e) {
    final b = e.response?.data;
    if (b is String && b.trim().isNotEmpty) {
      final t = b.trim();
      return '${e.message ?? e}（${t.length > 200 ? '${t.substring(0, 200)}…' : t}）';
    }
    return e.message ?? '$e';
  }

  /// 将 Dio 的 [data] 转为 JSON 对象（Map）。支持已是 Map、或 UTF-8 字符串体（再 `jsonDecode`）。
  static Map<String, dynamic> _parseResponseBodyAsJsonMap(dynamic data, {int? statusCode}) {
    if (data == null) {
      throw UpdateCheckException('空响应', statusCode: statusCode);
    }
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      var t = data.trim();
      if (t.startsWith('\uFEFF')) t = t.substring(1);
      if (t.isEmpty) throw UpdateCheckException('空响应体', statusCode: statusCode);
      final decoded = jsonDecode(t);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw FormatException('根节点不是 JSON 对象，而是 ${decoded.runtimeType}');
    }
    throw FormatException('无法解析的类型: ${data.runtimeType}');
  }

  static UpdateCheckClientDecision _decide(
    UpdateCheckResponse r,
    Version currentVersion,
    int currentBuild,
  ) {
    final release = r.latestRelease;
    if (release == null) {
      return UpdateCheckClientDecision(
        response: r,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        updateAvailable: false,
        forceUpdate: false,
        belowMinSupported: false,
        shouldVerifyIntegrity: false,
        compareNote: '无 latest_release',
      );
    }

    Version latest;
    try {
      latest = Version.parse(release.semanticVersion);
    } on FormatException {
      return UpdateCheckClientDecision(
        response: r,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        updateAvailable: false,
        forceUpdate: false,
        belowMinSupported: false,
        shouldVerifyIntegrity: false,
        compareNote: '服务端版本号格式无效: ${release.semanticVersion}',
      );
    }
    var belowMin = false;
    if (release.minSupportedSemanticVersion != null) {
      try {
        final minV = Version.parse(release.minSupportedSemanticVersion!);
        if (currentVersion < minV) belowMin = true;
      } on FormatException {
        // 服务端 min 版本格式异常则忽略该约束
      }
    }

    /// 仅按语义化版本比较，不比较 build。
    final hasNewer = latest > currentVersion;

    /// 以本地版本比较为主；`belowMin` 必须提示；`update_available=false` 可作灰度闸（仍低于最低版本时无视）。
    final gatedOff = r.serverUpdateAvailable == false && !belowMin;
    final updateAvailable = !gatedOff && (hasNewer || belowMin);

    final force = belowMin || release.updatePolicy == 'force';
    final integrity = release.artifact?.integrity;
    final verify = integrity != null &&
        (integrity.algorithm == 'sha256' ||
            integrity.algorithm == 'md5' ||
            integrity.algorithm == 'sha1');

    return UpdateCheckClientDecision(
      response: r,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      updateAvailable: updateAvailable,
      forceUpdate: force && updateAvailable,
      belowMinSupported: belowMin,
      shouldVerifyIntegrity: verify,
      compareNote: updateAvailable ? null : '已是最新版本 $currentVersion',
    );
  }
}

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message, {this.code, this.statusCode, this.response});

  final String message;
  final String? code;
  final int? statusCode;
  final UpdateCheckResponse? response;

  @override
  String toString() => 'UpdateCheckException($message, code=$code, status=$statusCode)';
}
