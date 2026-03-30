import 'dart:convert';

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
  static const _kDebugMode = 'debug_mode';
  static const _kPending = 'pending_sessions';
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
}
