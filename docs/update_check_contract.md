# 独立更新检查契约（`updatecheckfox`）

本文档描述 Flutter 客户端与 **`https://imm2.top/updatecheckfox`**（可替换为 `--dart-define=UPDATE_CHECK_URL`）之间的 **HTTP API**，不涉及签到系统主后端。服务端可自行选用静态 JSON、边缘函数或任意语言实现。

---

## 1. 传输与安全基线

| 项 | 要求 |
|----|------|
| 方法 | **POST** |
| `Content-Type` | `application/json` |
| TLS | **HTTPS**（必选），建议使用有效证书 |
| 鉴权 | 当前客户端 **不** 带业务 Cookie；若需防刷，可在网关层对 IP / 设备指纹限流 |

---

## 2. Request 结构（客户端 → 服务端）

与 Dart `UpdateCheckRequest` 对齐，JSON 字段如下（**snake_case**）：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `schema_version` | int | 是 | 契约版本，当前为 **1** |
| `app_channel` | string | 是 | 产品标识，默认 `sign_in_mobile`，与 `UPDATE_CHECK_APP_CHANNEL` 一致 |
| `platform` | string | 是 | `android` / `ios` / `other` |
| `current_semantic_version` | string | 是 | 语义版本，如 `1.0.0`（与 `pubspec` / PackageInfo 一致） |
| `current_build_number` | int | 是 | 构建号（与 PackageInfo `buildNumber` 一致） |
| `locale` | string | 否 | 默认 `zh_CN` |
| `os_version` | string | 否 | 客户端传的简短系统信息 |
| `device_model` | string | 否 | 注意隐私合规，可不用 |
| `installer_package` | string | 否 | Android 安装来源包名 |
| `client_capabilities` | string[] | 否 | 客户端能力，如 `semver_compare`、`sha256_verify` |
| `extra` | object | 否 | 扩展 |

### 请求示例

```json
{
  "schema_version": 1,
  "app_channel": "sign_in_mobile",
  "platform": "android",
  "current_semantic_version": "1.0.0",
  "current_build_number": 1,
  "locale": "zh_CN",
  "os_version": "platform:android",
  "client_capabilities": ["semver_compare", "sha256_verify"]
}
```

---

## 3. Response 结构（服务端 → 客户端）

整体可为：

- **扁平对象**；或
- `{ "success": true, "data": { ... 与下列相同 ... } }`（客户端会自动 unwrap `data`）

### 顶层字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `schema_version` | int | 建议返回 **1** |
| `success` | bool | 业务成功；`false` 时客户端抛错并展示 `error_message` |
| `error_code` | string | 可选，机器可读 |
| `error_message` | string | 人类可读 |
| `update_available` | bool | **可选**。`false` 且非「低于最低支持版本」时，客户端 **不** 提示更新（用于灰度关闸）；缺省则完全由版本号比较决定 |
| `latest_release` | object | 见下表 |

### `latest_release` 对象

| 字段 | 类型 | 说明 |
|------|------|------|
| `semantic_version` | string | 线上最新语义版本，如 `3.0.0` |
| `build_number` | int | 最新构建号 |
| `min_supported_semantic_version` | string | 可选，低于则视为「必须升级」 |
| `min_supported_build_number` | int | 可选，与 min 语义版本同线时比较 build |
| `delivery_mode` | string | **`full`**：全量包；**`delta`**：增量（客户端当前仅展示） |
| `update_policy` | string | **`suggest`** / **`force`** / `silent`；**`force`** 或低于最低版本时对话框强调 |
| `reason_code` | string | 可选，如 `NEWER_VERSION_PUBLISHED`、`MIN_VERSION_SUNSET` |
| `artifact` | object | 见下 |
| `changelog_markdown` | string | 可选，更新说明 Markdown |
| `changelog_entries` | array | 可选，结构化列表，见客户端模型 |

### `artifact` 对象

| 字段 | 类型 | 说明 |
|------|------|------|
| `kind` | string | 如 `apk` / `ipa` |
| `download_url` | string | **HTTPS 推荐**；客户端会尝试用浏览器打开 |
| `file_bytes` | int | 可选，字节数 |
| `integrity` | object | 可选但 **强烈建议**，见下 |

### `integrity` 对象（防篡改与完整性）

| 字段 | 类型 | 说明 |
|------|------|------|
| `algorithm` | string | **`sha256`**（推荐）/ `md5` / `sha1` |
| `hex_digest` | string | 与算法对应的小写十六进制摘要 |
| `manifest_signature_algorithm` | string | 可选，如 `ed25519`、`rsa-sha256` |
| `manifest_signature_base64` | string | 可选，对「发布清单 JSON」的二进制签名 |

---

## 4. 防篡改与校验时机（MD5 / SHA-256）

| 阶段 | 动作 |
|------|------|
| 传输 | **HTTPS** 防止链路篡改；证书固定（可选）进一步加固 |
| 元数据 | 若使用 `manifest_signature_*`，客户端可在解析 JSON 后用公钥验签（当前仓库 **未实现**验签，仅保留字段） |
| **下载完成后** | 对本地临时文件计算 `algorithm` 摘要，与 `hex_digest` 比较（见 `lib/utils/update_artifact_integrity.dart`） |
| **安装前** | 仅在校验通过后再调起系统安装；失败则 **删除临时文件** |
| Fallback | 若响应 **无** `integrity`，客户端仍可出现「前往下载」，但 **无法** 自动验真；建议在 UI 提示「请从可信渠道安装」 |

**建议**：新线统一 **SHA-256**；MD5 仅兼容老 CDN。

---

## 5. 跨版本升级策略（边界条件）

| 场景 | 服务端建议 |
|------|------------|
| 用户从 **v1.0 直接到 v3.0**（跳过多个中间版） | `delivery_mode` 固定为 **`full`**，只给一个 **完整 APK/IPA** 的 `download_url`，不要用依赖历史链的增量包 |
| 仅小版本 | 仍可 `full`；若你方有增量能力，可 `delta`，但须自行保证客户端兼容 |
| 老版本已不可连网 | 用 `min_supported_semantic_version` + `update_policy=force` 强制提示 |

客户端对 `delivery_mode` 仅作 **说明性展示**；安装 pipeline 由你方应用商店或侧载流程决定。

---

## 6. 成功响应示例

```json
{
  "schema_version": 1,
  "success": true,
  "update_available": true,
  "latest_release": {
    "semantic_version": "3.0.0",
    "build_number": 42,
    "min_supported_semantic_version": "1.0.0",
    "delivery_mode": "full",
    "update_policy": "suggest",
    "reason_code": "NEWER_VERSION_PUBLISHED",
    "artifact": {
      "kind": "apk",
      "download_url": "https://imm2.top/releases/sign-in-mobile-3.0.0.apk",
      "file_bytes": 25165824,
      "integrity": {
        "algorithm": "sha256",
        "hex_digest": "abcdef..."
      }
    },
    "changelog_markdown": "## 3.0.0\n- 跨大版本合并\n- 详见官网",
    "changelog_entries": [
      {
        "version": "3.0.0",
        "build": 42,
        "date_iso": "2026-03-30",
        "highlights": ["全量包", "修复历史列表卡顿"]
      }
    ]
  }
}
```

---

## 7. Flutter 工程内对应文件

| 文件 | 作用 |
|------|------|
| `lib/models/update_check_models.dart` | Request / Response DTO |
| `lib/services/update_check_service.dart` | HTTP 调用与版本决策 |
| `lib/utils/update_artifact_integrity.dart` | 下载后文件摘要校验工具 |
| `lib/widgets/update_check_flow.dart` | 设置页「检查更新」UI |
| `lib/config/app_config.dart` | `updateCheckUrl` / `updateCheckAppChannel` |

覆盖 URL：`flutter run --dart-define=UPDATE_CHECK_URL=https://你的域名/路径`
