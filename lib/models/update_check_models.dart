import 'package:pub_semver/pub_semver.dart';

/// 客户端 → 更新检查服务（`AppConfig.updateCheckUrl`）POST JSON 请求体。
///
/// **跨版本策略**：服务端根据 `current_*` 与最新线的差距决定 `delivery_mode`：
/// - `full`：下发完整安装包（典型：v1.0 → v3.0 或跳过多个中间版）。
/// - `delta`：增量包（若你方实现；客户端当前仅识别并提示，安装逻辑可自行扩展）。
class UpdateCheckRequest {
  const UpdateCheckRequest({
    required this.schemaVersion,
    required this.appChannel,
    required this.platform,
    required this.currentSemanticVersion,
    required this.currentBuildNumber,
    this.locale = 'zh_CN',
    this.osVersion,
    this.deviceModel,
    this.installerPackage,
    this.clientCapabilities = const ['semver_compare', 'sha256_verify'],
    this.extra = const {},
  });

  /// 契约版本；与服务端对齐，便于演进字段。
  final int schemaVersion;

  /// 产品通道，与 [`AppConfig.updateCheckAppChannel`] 一致。
  final String appChannel;

  /// `android` | `ios` | `other`
  final String platform;

  /// 当前 **语义化版本**（与 `pubspec` / PackageInfo `version` 对齐，如 `1.0.0`）。
  final String currentSemanticVersion;

  /// 当前构建号（与 PackageInfo `buildNumber` 对齐）。
  final int currentBuildNumber;

  /// BCP47 风格语言区域，便于服务端返回本地化 release notes。
  final String locale;

  /// 操作系统版本字符串（如 Android SDK 级别拼接），可选。
  final String? osVersion;

  /// 机型，可选；注意隐私合规。
  final String? deviceModel;

  /// 安装来源包名（Android `installerPackageName`），可选。
  final String? installerPackage;

  /// 客户端能力声明，供服务端决定是否下发 delta / 签名验真等。
  final List<String> clientCapabilities;

  /// 扩展字段，不落库时可留空。
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'app_channel': appChannel,
        'platform': platform,
        'current_semantic_version': currentSemanticVersion,
        'current_build_number': currentBuildNumber,
        'locale': locale,
        if (osVersion != null) 'os_version': osVersion,
        if (deviceModel != null) 'device_model': deviceModel,
        if (installerPackage != null) 'installer_package': installerPackage,
        'client_capabilities': clientCapabilities,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

/// 安装工件完整性描述。
///
/// **校验时机（推荐）**：
/// 1. 仅在 **文件下载完成、写入磁盘结束后** 对本地文件做摘要计算（MD5 或 SHA-256）。
/// 2. **在安装/覆盖安装之前** 比对 `hex_digest`；不匹配则删除临时文件并提示「可能被篡改或下载损坏」。
/// 3. MD5 仅作兼容；新线产品建议统一 **SHA-256**。
/// 4. `manifest_signature_*` 可选：用于校验 JSON 清单本身未被篡改（与 HTTPS 证书链互补）。
class UpdateArtifactIntegrity {
  const UpdateArtifactIntegrity({
    required this.algorithm,
    required this.hexDigest,
    this.manifestSignatureAlgorithm,
    this.manifestSignatureBase64,
  });

  /// `sha256` | `md5` | `sha1`（客户端对 `sha256` / `md5` 提供工具方法）。
  final String algorithm;

  /// 与 [algorithm] 对应的小写十六进制摘要字符串。
  final String hexDigest;

  final String? manifestSignatureAlgorithm;
  final String? manifestSignatureBase64;

  static UpdateArtifactIntegrity? tryParse(Object? json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    final algo = m['algorithm'] as String?;
    final digest = m['hex_digest'] as String? ?? m['hexDigest'] as String?;
    if (algo == null || digest == null || algo.isEmpty || digest.isEmpty) return null;
    return UpdateArtifactIntegrity(
      algorithm: algo.toLowerCase(),
      hexDigest: digest,
      manifestSignatureAlgorithm: m['manifest_signature_algorithm'] as String?,
      manifestSignatureBase64: m['manifest_signature_base64'] as String?,
    );
  }
}

/// 可下载的安装包元数据。
class UpdateArtifact {
  const UpdateArtifact({
    required this.kind,
    required this.downloadUrl,
    this.fileBytes,
    this.integrity,
  });

  /// `apk` | `ipa` | `aab` | `msix` 等
  final String kind;

  /// **须为 HTTPS**（客户端可配置严格校验）。
  final String downloadUrl;

  /// 字节长度，便于展示与断点续传扩展。
  final int? fileBytes;

  final UpdateArtifactIntegrity? integrity;

  static UpdateArtifact? tryParse(Object? json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    final kind = m['kind'] as String? ?? 'apk';
    final url = m['download_url'] as String? ?? m['downloadUrl'] as String?;
    if (url == null || url.isEmpty) return null;
    final bytes = (m['file_bytes'] as num?)?.toInt() ?? (m['fileBytes'] as num?)?.toInt();
    return UpdateArtifact(
      kind: kind,
      downloadUrl: url,
      fileBytes: bytes,
      integrity: UpdateArtifactIntegrity.tryParse(m['integrity']),
    );
  }
}

/// 单条更新日志（结构化，便于列表展示）。
class UpdateChangelogEntry {
  const UpdateChangelogEntry({
    required this.version,
    required this.build,
    this.dateIso,
    this.highlights = const [],
  });

  final String version;
  final int build;
  final String? dateIso;
  final List<String> highlights;

  static UpdateChangelogEntry? tryParse(Object? json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    final v = m['version'] as String? ?? m['semantic_version'] as String?;
    final b = (m['build'] as num?)?.toInt() ?? (m['build_number'] as num?)?.toInt() ?? 0;
    if (v == null) return null;
    final hi = m['highlights'];
    final List<String> list = [];
    if (hi is List) {
      for (final e in hi) {
        if (e != null) list.add('$e');
      }
    }
    return UpdateChangelogEntry(
      version: v,
      build: b,
      dateIso: m['date_iso'] as String? ?? m['dateIso'] as String?,
      highlights: list,
    );
  }
}

/// 服务端认定的「最新发布」。
class UpdateLatestRelease {
  const UpdateLatestRelease({
    required this.semanticVersion,
    required this.buildNumber,
    this.minSupportedSemanticVersion,
    this.minSupportedBuildNumber,
    this.deliveryMode = 'full',
    this.updatePolicy = 'suggest',
    this.reasonCode,
    this.artifact,
    this.changelogMarkdown,
    this.changelogEntries = const [],
  });

  final String semanticVersion;
  final int buildNumber;

  /// 低于此语义版本的客户端：建议服务端 `update_policy=force` 或单独字段提示停服。
  final String? minSupportedSemanticVersion;

  final int? minSupportedBuildNumber;

  /// `full`：全量包（**跨多版本升级时服务端应固定返回 full**）。
  /// `delta`：增量（若启用）。
  final String deliveryMode;

  /// `suggest` | `force` | `silent`
  final String updatePolicy;

  /// 机器可读原因码，如 `NEWER_VERSION_PUBLISHED`、`MIN_VERSION_SUNSET`。
  final String? reasonCode;

  final UpdateArtifact? artifact;

  /// 完整 Markdown 说明（客户端可做简单文本展示）。
  final String? changelogMarkdown;

  final List<UpdateChangelogEntry> changelogEntries;

  static UpdateLatestRelease? tryParse(Object? json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    final ver = m['semantic_version'] as String? ?? m['semanticVersion'] as String?;
    final build = (m['build_number'] as num?)?.toInt() ?? (m['buildNumber'] as num?)?.toInt() ?? 0;
    if (ver == null) return null;
    final entriesRaw = m['changelog_entries'] ?? m['changelogEntries'];
    final entries = <UpdateChangelogEntry>[];
    if (entriesRaw is List) {
      for (final e in entriesRaw) {
        final ce = UpdateChangelogEntry.tryParse(e);
        if (ce != null) entries.add(ce);
      }
    }
    return UpdateLatestRelease(
      semanticVersion: ver,
      buildNumber: build,
      minSupportedSemanticVersion: m['min_supported_semantic_version'] as String? ??
          m['minSupportedSemanticVersion'] as String?,
      minSupportedBuildNumber: (m['min_supported_build_number'] as num?)?.toInt() ??
          (m['minSupportedBuildNumber'] as num?)?.toInt(),
      deliveryMode: (m['delivery_mode'] as String? ?? m['deliveryMode'] as String? ?? 'full').toLowerCase(),
      updatePolicy: (m['update_policy'] as String? ?? m['updatePolicy'] as String? ?? 'suggest').toLowerCase(),
      reasonCode: m['reason_code'] as String? ?? m['reasonCode'] as String?,
      artifact: UpdateArtifact.tryParse(m['artifact']),
      changelogMarkdown: m['changelog_markdown'] as String? ?? m['changelogMarkdown'] as String?,
      changelogEntries: entries,
    );
  }
}

/// 服务原始响应（成功或业务错误）。
class UpdateCheckResponse {
  const UpdateCheckResponse({
    required this.schemaVersion,
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.serverUpdateAvailable,
    this.latestRelease,
    this.raw,
  });

  final int schemaVersion;
  final bool success;
  final String? errorCode;
  final String? errorMessage;

  /// 服务端是否「认为」有新版本；缺省为 null 表示不拦客户端根据版本号自行判断。
  final bool? serverUpdateAvailable;
  final UpdateLatestRelease? latestRelease;

  /// 原始 JSON 便于排错。
  final Map<String, dynamic>? raw;

  static Map<String, dynamic> _unwrap(Map<String, dynamic> j) {
    final d = j['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return j;
  }

  factory UpdateCheckResponse.fromJson(Map<String, dynamic> json) {
    final j = _unwrap(json);
    final success = j['success'] as bool? ?? j['ok'] as bool? ?? false;
    final avail = j['update_available'] as bool? ?? j['updateAvailable'] as bool?;
    final release = UpdateLatestRelease.tryParse(j['latest_release'] ?? j['latestRelease']);
    return UpdateCheckResponse(
      schemaVersion: (j['schema_version'] as num?)?.toInt() ?? (j['schemaVersion'] as num?)?.toInt() ?? 1,
      success: success,
      errorCode: j['error_code'] as String? ?? j['errorCode'] as String?,
      errorMessage: j['error_message'] as String? ?? j['errorMessage'] as String?,
      serverUpdateAvailable: avail,
      latestRelease: release,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// 客户端在解析 [UpdateCheckResponse] 之后做的 **最终决策**（含版本比较）。
class UpdateCheckClientDecision {
  const UpdateCheckClientDecision({
    required this.response,
    required this.currentVersion,
    required this.currentBuild,
    required this.updateAvailable,
    required this.forceUpdate,
    required this.belowMinSupported,
    required this.shouldVerifyIntegrity,
    this.compareNote,
  });

  final UpdateCheckResponse response;
  final Version currentVersion;
  final int currentBuild;
  final bool updateAvailable;
  final bool forceUpdate;

  /// 当前客户端低于服务端 `min_supported_*`。
  final bool belowMinSupported;

  /// 若存在 [UpdateArtifact.integrity] 且 algorithm 受支持，则下载完成后应校验。
  final bool shouldVerifyIntegrity;

  final String? compareNote;
}
