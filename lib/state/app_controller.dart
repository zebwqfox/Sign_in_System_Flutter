import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/audit_service.dart';
import '../services/storage_service.dart';

class AppController extends ChangeNotifier {
  AppController({required this.api, required this.storage})
      : themeMode = storage.themeMode,
        themeColorMode = storage.themeColorMode,
        themeSeedColor = storage.themeSeedColor,
        debugMode = storage.debugModeEnabled {
    authListenable.value = storage.isLoggedIn;
    api.setOnUnauthorized(_onSessionUnauthorizedFromApi);
  }

  final ApiService api;
  final StorageService storage;
  bool _handlingUnauthorized = false;

  String _packageVersionLabel = '—';
  bool _studentsBootstrapPending = false;

  ThemeMode themeMode;
  String themeColorMode;
  int themeSeedColor;
  bool debugMode;

  final ValueNotifier<bool> authListenable = ValueNotifier(false);

  List<Student> students = [];
  bool busy = false;
  String? snackMessage;
  bool snackError = false;

  String draftSessionName = '';
  List<AttendanceRecord> draftRecords = [];

  String completedSessionName = '';
  List<AttendanceRecord> completedRecords = [];
  String? completedSessionId;
  bool completedIsLocal = false;

  bool get isHomeDataBootstrapping => _studentsBootstrapPending;

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

  Future<void> setThemeColorMode(String mode) async {
    final v = (mode == 'custom') ? 'custom' : 'monet';
    await storage.setThemeColorMode(v);
    themeColorMode = v;
    notifyListeners();
  }

  Future<void> setThemeSeedColor(int colorValue) async {
    await storage.setThemeSeedColor(colorValue);
    themeSeedColor = colorValue;
    notifyListeners();
  }

  Future<void> setDebugMode(bool enabled) async {
    await storage.setDebugModeEnabled(enabled);
    debugMode = enabled;
    notifyListeners();
  }

  Future<void> login(String password) async {
    unawaited(AuditService.instance.logEvent(
      category: 'auth',
      action: 'login_attempt',
      feature: 'login',
    ));
    _setBusy(true);
    try {
      await api.warmupEdgeSession();
      final sessionId = await api.login(password);
      await storage.persistLoginSession(sessionId);
      api.setAuthToken(sessionId);
      authListenable.value = true;
      await refreshStudents(silent: true);
      notifyListeners();
      unawaited(AuditService.instance.logEvent(
        category: 'auth',
        action: 'login_success',
        feature: 'login',
      ));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    unawaited(AuditService.instance.logEvent(
      category: 'auth',
      action: 'logout',
      feature: 'settings',
    ));
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
