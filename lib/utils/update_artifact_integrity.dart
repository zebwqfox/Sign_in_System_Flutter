import 'dart:io';

import 'package:crypto/crypto.dart';

/// 安装包完整性校验（**下载完成后、安装前**调用）。
///
/// **推荐时机**
/// - 下载线程结束、文件落盘、`File.length` 与响应 `file_bytes`（若有）一致后，再计算摘要。
/// - **通过后再** 调起系统安装器；失败则删除临时文件并提示，避免被篡改包或损坏包进入系统安装流程。
///
/// **MD5 / SHA-256**
/// - 新线统一 **SHA-256**；MD5 仅作兼容。
/// - 与 **HTTPS** 配合：TLS 保证传输，摘要保证源站/对象存储内容一致。
class UpdateArtifactIntegrityVerifier {
  UpdateArtifactIntegrityVerifier._();

  /// 返回 `null` 表示校验通过，否则为可读错误原因。
  static Future<String?> verifyFile({
    required String filePath,
    required String algorithm,
    required String expectedHexDigest,
  }) async {
    final algo = algorithm.toLowerCase().trim();
    final expected = expectedHexDigest.toLowerCase().replaceAll(RegExp(r'\s'), '');

    late Digest digest;
    final file = File(filePath);
    if (!await file.exists()) {
      return '文件不存在';
    }
    switch (algo) {
      case 'sha256':
        digest = await sha256.bind(file.openRead()).first;
        break;
      case 'md5':
        digest = await md5.bind(file.openRead()).first;
        break;
      case 'sha1':
        digest = await sha1.bind(file.openRead()).first;
        break;
      default:
        return '不支持的算法: $algorithm';
    }

    final got = digest.toString();
    if (got != expected) {
      return '摘要不匹配（期望 $expected 实际 $got），已中止安装';
    }
    return null;
  }
}
