/// 与 Vue 前端 `VITE_API_URL` 对齐；可通过 `--dart-define=API_BASE=...` 覆盖。
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://hbust.imm2.top/api',
  );

  /// 分享链接使用站点根路径（去掉末尾 `/api`），与 Web `window.location.origin` 一致。
  static String get shareBaseUrl {
    var u = apiBaseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (u.endsWith('/api')) return u.substring(0, u.length - 4);
    return u;
  }

  /// 与业务 API 独立；可通过 `--dart-define=UPDATE_CHECK_URL=...` 覆盖。
  /// 默认带 **尾斜杠**，避免服务器 301 到 `/updatecheckfox/` 时部分环境下 POST 重定向异常。
  static const String updateCheckUrl = String.fromEnvironment(
    'UPDATE_CHECK_URL',
    defaultValue: 'https://imm2.top/updatecheckfox/',
  );

  /// 上报给更新通道的产品标识，便于同一检查 URL 服务多个 App。
  static const String updateCheckAppChannel = String.fromEnvironment(
    'UPDATE_CHECK_APP_CHANNEL',
    defaultValue: 'sign_in_mobile',
  );

  /// 审计上报接口（独立 audit-backend 的 /api/audit/upload）。
  /// 可通过 --dart-define 覆盖。
  static const String auditUploadUrl = String.fromEnvironment(
    'AUDIT_UPLOAD_URL',
    defaultValue: 'http://audit_hbust.imm2.top/api/audit/upload',
  );

  /// 可选：与 audit-backend 的 AUDIT_UPLOAD_TOKEN 对应。
  static const String auditUploadToken = String.fromEnvironment(
    'AUDIT_UPLOAD_TOKEN',
    defaultValue: '',
  );

  /// DeepSeek AI 锐评接口配置（建议通过 --dart-define 注入，避免写死密钥）。
  static const String aiReviewApiBase = String.fromEnvironment(
    'AI_REVIEW_API_BASE',
    defaultValue: 'https://api.deepseek.com',
  );

  static const String aiReviewModel = String.fromEnvironment(
    'AI_REVIEW_MODEL',
    defaultValue: 'deepseek-reasoner',
  );

  static const String aiReviewApiKey = String.fromEnvironment(
    'AI_REVIEW_API_KEY',
    defaultValue: 'sk-7c5ae15f1acb46138bfe6fd24f3f5bf5',
  );
}
