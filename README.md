# 签到助手（Flutter 客户端）

移动端签到系统客户端，支持点名流程、历史记录、统计报表、学生名册管理、应用内更新与审计采集。

---

## 功能概览

- 登录与会话管理（基于后端 token/session）
- 点名流程（语音朗读、拼音辅助、状态修正、总览）
- 点名结算（导出 Excel、异常名单分组、全勤撒花）
- 历史记录（本地/云端合并、详情编辑、索引条）
- 统计报表（搜索、排序、明细页）
- 学生名册管理（成员列表、批量导入、批量删除）
- 设置中心
  - 明暗/系统主题
  - Android 12+ 莫奈取色 + 自选主题色
  - 开发者信息页
- 更新能力
  - 启动检查更新
  - 应用内下载 APK 与安装引导
- 审计能力
  - 本地采集设备/位置/操作
  - 启动静默增量上传到独立审计服务

---

## 环境要求

- Flutter SDK（建议与仓库当前开发环境一致）
- Dart SDK（由 Flutter 自带）
- Android Studio / VS Code（任一）
- Android 设备或模拟器（Android 8+，建议 Android 12+）

---

## 本地运行

在项目根目录执行：

```bash
cd mobile_flutter
flutter pub get
flutter run
```

---

## 打包发布（Release APK）

```bash
cd mobile_flutter
flutter build apk --release
```

产物路径：

`build/app/outputs/flutter-apk/app-release.apk`

---

## 常用 dart-define

可在 `flutter run` / `flutter build` 时附加：

```bash
--dart-define=API_BASE=https://你的后端/api
--dart-define=UPDATE_CHECK_URL=https://你的更新检查地址/
--dart-define=UPDATE_CHECK_APP_CHANNEL=sign_in_mobile
--dart-define=AUDIT_UPLOAD_URL=http://你的审计服务/api/audit/upload
--dart-define=AUDIT_UPLOAD_TOKEN=可选token
```

---

## 审计上传说明

- 客户端会本地缓存审计事件。
- 启动后会静默增量上传（不阻塞首屏）。
- 上传地址由 `AUDIT_UPLOAD_URL` 控制。
- 审计看板建议配合独立服务 `audit-backend` 使用。

---

## 更新机制说明

- 启动后延迟检查更新。
- 强制更新会弹出阻断式更新弹窗。
- Android 支持应用内下载并拉起系统安装器。
- 需授予“安装未知应用”权限。

---

## 目录结构（核心）

```text
lib/
  config/                # 配置与 dart-define 入口
  models/                # 数据模型
  router/                # 路由与页面转场
  screens/               # 页面
  services/              # API、审计、更新、存储等服务
  state/                 # 全局状态（AppController）
  theme/                 # 主题系统（含莫奈/自定义色）
  utils/                 # 工具类
  widgets/               # 通用组件
```

---

## 常见问题

### 1) 启动慢/卡住

- 已将非关键任务延后并异步执行。
- 如果仍慢，优先检查设备定位服务状态、网络质量与首次安装后的系统权限弹窗。

### 2) 更新下载失败

- 检查更新源是否可访问。
- 检查 Android “安装未知应用”权限是否已开启。

### 3) 审计看板没数据

- 检查 `AUDIT_UPLOAD_URL` 是否正确。
- 检查审计服务是否在线（`/api/health`）。

---

## 备注

本目录 README 仅描述 Flutter 客户端。  
Web 端、原 Node 后端、独立审计后端请查看项目根目录对应子项目文档。
