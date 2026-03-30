import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AppController extends ChangeNotifier {
  AppController({required this.api, required this.storage})
      : themeMode = storage.themeMode,
        debugMode = storage.debugModeEnabled {
    authListenable.value = storage.isLoggedIn;
    api.setOnUnauthorized(_onSessionUnauthorizedFromApi);
  }

  final ApiService api;
  final StorageService storage;
  bool _handlingUnauthorized = false;

  /// 与 `pubspec.yaml` 的 `version` 一致（在 [warmStartAfterFirstFrame] 里填充）。
  String _packageVersionLabel = '—';

  /// 已登录时，首帧后拉取名册进行中（用于首页占位，避免误点「开始」）。
  bool _studentsBootstrapPending = false;

  ThemeMode themeMode;

  /// 调试模式：登录失败展示原始异常；设置页显示开发者选项。
  bool debugMode;

  /// 仅登录状态变化时通知，避免 GoRouter 因 Toast 等频繁重建。
  final ValueNotifier<bool> authListenable = ValueNotifier(false);

  List<Student> students = [];
  bool busy = false;
  String? snackMessage;
  bool snackError = false;

  /// 当前进行中的点名（首页「开始」到提交前）
  String draftSessionName = '';
  List<AttendanceRecord> draftRecords = [];

  /// 最近一次提交结果（总结页）
  String completedSessionName = '';
  List<AttendanceRecord> completedRecords = [];
  String? completedSessionId;
  bool completedIsLocal = false;

  bool get isHomeDataBootstrapping => _studentsBootstrapPending;

  /// 在 [runApp] 之后、首帧回调中执行：不阻塞首屏，缩短白屏/闪屏感知时间。
  Future<void> warmStartAfterFirstFrame() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final b = info.buildNumber.trim();
      _packageVersionLabel = (b.isEmpty || b == '0') ? info.version : '${info.version}+$b';
      notifyListeners();
    } catch (_) {
      _packageVersionLabel = '—';
      notifyListeners();
    }

    if (!storage.isLoggedIn) return;

    final sid = storage.authSessionId;
    if (sid != null && sid.isNotEmpty) {
      api.setAuthToken(sid);
    }
    _studentsBootstrapPending = true;
    notifyListeners();
    try {
      await api.warmupEdgeSession();
      await refreshStudents(silent: true);
    } finally {
      _studentsBootstrapPending = false;
      notifyListeners();
    }
  }

  bool get isLoggedIn => storage.isLoggedIn;

  bool get voiceEnabled => storage.voiceEnabled;

  bool get pinyinEnabled => storage.pinyinEnabled;

  Future<void> setVoiceEnabled(bool v) async {
    await storage.setVoiceEnabled(v);
    notifyListeners();
  }

  Future<void> setPinyinEnabled(bool v) async {
    await storage.setPinyinEnabled(v);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await storage.setThemeMode(mode);
    themeMode = mode;
    notifyListeners();
  }

  Future<void> setDebugMode(bool enabled) async {
    await storage.setDebugModeEnabled(enabled);
    debugMode = enabled;
    notifyListeners();
  }

  Future<void> login(String password) async {
    _setBusy(true);
    try {
      await api.warmupEdgeSession();
      final sessionId = await api.login(password);
      await storage.persistLoginSession(sessionId);
      api.setAuthToken(sessionId);
      authListenable.value = true;
      await refreshStudents(silent: true);
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    api.setAuthToken(null);
    await storage.clearLogin();
    authListenable.value = false;
    students = [];
    notifyListeners();
  }

  void _onSessionUnauthorizedFromApi() {
    if (_handlingUnauthorized || !storage.isLoggedIn) return;
    _handlingUnauthorized = true;
    unawaited(
      logout().whenComplete(() {
        _handlingUnauthorized = false;
      }),
    );
  }

  Future<void> refreshStudents({bool silent = false}) async {
    try {
      students = await api.fetchStudents();
      notifyListeners();
    } catch (e) {
      if (!silent) {
        _toast('$e', error: true);
      }
    }
  }

  void beginDraftSession(String name) {
    draftSessionName = name;
    draftRecords = [];
    notifyListeners();
  }

  void setCompleted({
    required String name,
    required List<AttendanceRecord> records,
    required String? sessionId,
    required bool isLocal,
  }) {
    completedSessionName = name;
    completedRecords = records.map((e) => e.copy()).toList();
    completedSessionId = sessionId;
    completedIsLocal = isLocal;
    notifyListeners();
  }

  void _toast(String msg, {bool error = false}) {
    snackMessage = msg;
    snackError = error;
    notifyListeners();
  }

  /// 仅清状态，不触发 [notifyListeners]。若在 [notifyListeners] 派发的监听里再次 notify
  ///（例如 main 里 showSnackBar 后立刻 clear），会导致 Provider 重入并触发
  /// `_dependents.isEmpty` 断言。
  void clearSnack() {
    snackMessage = null;
    snackError = false;
  }

  void _setBusy(bool v) {
    busy = v;
    notifyListeners();
  }

  Future<void> withLoading(Future<void> Function() fn) async {
    _setBusy(true);
    try {
      await fn();
    } finally {
      _setBusy(false);
    }
  }

  String get localVersionLabel => _packageVersionLabel;
}
