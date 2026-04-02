import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class StorageService {
  StorageService._(this._p);

  final SharedPreferences _p;

  static Future<StorageService> create() async {
    final p = await SharedPreferences.getInstance();
    return StorageService._(p);
  }

  static const _kToken = 'login_token';
  static const _kExpire = 'login_expire';
  static const _kVoice = 'voice_enabled';
  static const _kPinyin = 'pinyin_enabled';
  static const _kThemeMode = 'theme_mode';
  static const _kThemeColorMode = 'theme_color_mode';
  static const _kThemeSeedColor = 'theme_seed_color';
  static const _kLegalAgreementAccepted = 'legal_agreement_accepted';
  static const _kDebugMode = 'debug_mode';
  static const _kPending = 'pending_sessions';
  static const _kInstallId = 'install_id';
  static const _kAuditEvents = 'audit_events';
  static const _kAuditLastUploadedTsMs = 'audit_last_uploaded_ts_ms';
  static const _kAiReviewCache = 'ai_review_cache_v1';
  static const _kCourseSchedule = 'course_schedule_v1';
  /// 与后端 `POST /api/login` 返回的 `data.sessionId` 一致，请求头 `x-auth-token` 使用。
  static const _kAuthSessionId = 'auth_session_id';

  bool get isLoggedIn {
    if (_p.getString(_kToken) != 'admin_ok') return false;
    if ((_p.getString(_kAuthSessionId) ?? '').isEmpty) return false;
    final exp = _p.getInt(_kExpire);
    if (exp == null) return false;
    return DateTime.now().millisecondsSinceEpoch < exp;
  }

  Future<void> setLoggedIn() async {
    await _p.setString(_kToken, 'admin_ok');
    final exp = DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000;
    await _p.setInt(_kExpire, exp);
  }

  String? get authSessionId => _p.getString(_kAuthSessionId);

  Future<void> setAuthSessionId(String sessionId) async {
    await _p.setString(_kAuthSessionId, sessionId);
  }

  /// 登录成功一次写入 sessionId + 标记 + 过期时间，避免分步写入时杀进程导致状态不一致。
  Future<void> persistLoginSession(String sessionId) async {
    final exp = DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000;
    await _p.setString(_kAuthSessionId, sessionId);
    await _p.setString(_kToken, 'admin_ok');
    await _p.setInt(_kExpire, exp);
  }

  Future<void> clearLogin() async {
    await _p.remove(_kToken);
    await _p.remove(_kExpire);
    await _p.remove(_kAuthSessionId);
  }

  bool get voiceEnabled => _p.getBool(_kVoice) ?? false;

  Future<void> setVoiceEnabled(bool v) => _p.setBool(_kVoice, v);

  bool get pinyinEnabled => _p.getBool(_kPinyin) ?? false;

  Future<void> setPinyinEnabled(bool v) => _p.setBool(_kPinyin, v);

  ThemeMode get themeMode {
    switch (_p.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _p.setString(_kThemeMode, v);
  }

  String get themeColorMode {
    final v = _p.getString(_kThemeColorMode) ?? 'monet';
    return (v == 'monet' || v == 'custom') ? v : 'monet';
  }

  Future<void> setThemeColorMode(String mode) async {
    final v = (mode == 'custom') ? 'custom' : 'monet';
    await _p.setString(_kThemeColorMode, v);
  }

  int get themeSeedColor => _p.getInt(_kThemeSeedColor) ?? 0xFF58CC02;

  Future<void> setThemeSeedColor(int colorValue) async {
    await _p.setInt(_kThemeSeedColor, colorValue);
  }

  bool get legalAgreementAccepted => _p.getBool(_kLegalAgreementAccepted) ?? false;

  Future<void> setLegalAgreementAccepted(bool accepted) async {
    await _p.setBool(_kLegalAgreementAccepted, accepted);
  }

  bool get debugModeEnabled => _p.getBool(_kDebugMode) ?? false;

  Future<void> setDebugModeEnabled(bool v) => _p.setBool(_kDebugMode, v);

  Future<List<LocalPendingSession>> loadPendingSessions() async {
    final raw = _p.getString(_kPending);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final sevenDaysAgo = DateTime.now().millisecondsSinceEpoch - 7 * 24 * 60 * 60 * 1000;
      final out = <LocalPendingSession>[];
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final created = DateTime.tryParse(m['created_at'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
        if (created > sevenDaysAgo) {
          out.add(LocalPendingSession.fromJson(m));
        }
      }
      if (out.length != list.length) {
        await savePendingSessions(out);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingSessions(List<LocalPendingSession> sessions) async {
    await _p.setString(_kPending, jsonEncode(sessions.map((e) => e.toJson()).toList()));
  }

  Future<void> removePendingById(String id) async {
    final all = await loadPendingSessions();
    await savePendingSessions(all.where((e) => e.id != id).toList());
  }

  Future<void> upsertPendingSession(LocalPendingSession session) async {
    final all = await loadPendingSessions();
    final idx = all.indexWhere((e) => e.id == session.id);
    if (idx >= 0) {
      all[idx] = session;
    } else {
      all.add(session);
    }
    await savePendingSessions(all);
  }

  Future<String> getOrCreateInstallId() async {
    final old = _p.getString(_kInstallId);
    if (old != null && old.isNotEmpty) return old;
    final r = Random.secure();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = List<int>.generate(12, (_) => r.nextInt(36))
        .map((e) => e.toRadixString(36))
        .join();
    final id = 'ins_${ts}_$rand';
    await _p.setString(_kInstallId, id);
    return id;
  }

  Future<void> appendAuditEvent(Map<String, dynamic> event, {int maxItems = 2000}) async {
    final raw = _p.getString(_kAuditEvents);
    final list = <dynamic>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        list.addAll(jsonDecode(raw) as List<dynamic>);
      } catch (_) {}
    }
    list.add(event);
    if (list.length > maxItems) {
      list.removeRange(0, list.length - maxItems);
    }
    await _p.setString(_kAuditEvents, jsonEncode(list));
  }

  List<Map<String, dynamic>> loadAuditEvents({int? limit}) {
    final raw = _p.getString(_kAuditEvents);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (limit == null || limit <= 0 || list.length <= limit) return list;
      return list.sublist(list.length - limit);
    } catch (_) {
      return [];
    }
  }

  Future<void> clearAuditEvents() async {
    await _p.remove(_kAuditEvents);
  }

  int get auditLastUploadedTsMs => _p.getInt(_kAuditLastUploadedTsMs) ?? 0;

  Future<void> setAuditLastUploadedTsMs(int tsMs) async {
    await _p.setInt(_kAuditLastUploadedTsMs, tsMs);
  }

  Future<String?> getAiReviewCache(String sessionId) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) return null;
    final raw = _p.getString(_kAiReviewCache);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final item = map[sid];
      if (item is! Map) return null;
      final text = (item['text'] ?? '').toString().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  Future<void> setAiReviewCache(
    String sessionId,
    String text, {
    int maxItems = 120,
  }) async {
    final sid = sessionId.trim();
    final content = text.trim();
    if (sid.isEmpty || content.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final raw = _p.getString(_kAiReviewCache);
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    map[sid] = {
      'text': content,
      'ts_ms': now,
    };

    if (map.length > maxItems) {
      final keys = map.keys.toList()
        ..sort((a, b) {
          final ta = ((map[a] as Map?)?['ts_ms'] as num?)?.toInt() ?? 0;
          final tb = ((map[b] as Map?)?['ts_ms'] as num?)?.toInt() ?? 0;
          return ta.compareTo(tb);
        });
      final removeCount = map.length - maxItems;
      for (var i = 0; i < removeCount; i++) {
        map.remove(keys[i]);
      }
    }

    await _p.setString(_kAiReviewCache, jsonEncode(map));
  }

  List<Map<String, dynamic>> getCourseSchedule() {
    final raw = _p.getString(_kCourseSchedule);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setCourseSchedule(List<Map<String, dynamic>> items) async {
    await _p.setString(_kCourseSchedule, jsonEncode(items));
  }

  Future<void> clearCourseSchedule() async {
    await _p.remove(_kCourseSchedule);
  }
}
