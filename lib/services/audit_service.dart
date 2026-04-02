import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'storage_service.dart';

class AuditService {
  AuditService._();
  static final AuditService instance = AuditService._();

  StorageService? _storage;
  String _installId = '';
  Map<String, dynamic> _deviceInfo = {};
  String _appVersion = '';
  String _currentRoute = '';

  Map<String, dynamic>? _lastLocation;
  DateTime _lastLocationAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _initDone = false;

  Future<void> init(StorageService storage) async {
    if (_initDone) return;
    _storage = storage;
    _installId = await storage.getOrCreateInstallId();
    _deviceInfo = await _collectDeviceInfo();
    _appVersion = await _collectAppVersion();
    _initDone = true;
    // 启动阶段避免阻塞首帧，改为后台记录；并跳过首次定位采集以降低启动耗时。
    unawaited(logEvent(
      category: 'app',
      action: 'app_start',
      feature: 'lifecycle',
      extra: {'boot': 'cold'},
      withLocation: false,
    ));
  }

  void setCurrentRoute(String routeName) {
    _currentRoute = routeName;
  }

  Future<void> logEvent({
    required String category,
    required String action,
    String? feature,
    Map<String, dynamic>? extra,
    bool withLocation = true,
  }) async {
    final storage = _storage;
    if (storage == null) return;
    final now = DateTime.now();
    final loc = withLocation
        ? await _getLocationSnapshot()
        : <String, dynamic>{
            'enabled': false,
            'permission': 'skipped',
            'lat': null,
            'lng': null,
            'accuracy': null,
          };
    final event = <String, dynamic>{
      'ts_ms': now.millisecondsSinceEpoch,
      'ts_iso': now.toIso8601String(),
      'install_id': _installId,
      'route': _currentRoute,
      'category': category,
      'feature': feature ?? '',
      'action': action,
      'app_version': _appVersion,
      'device': _deviceInfo,
      'location': loc,
      'extra': extra ?? <String, dynamic>{},
    };
    await storage.appendAuditEvent(event);
  }

  Future<List<Map<String, dynamic>>> readAuditEvents({int limit = 200}) async {
    final storage = _storage;
    if (storage == null) return [];
    return storage.loadAuditEvents(limit: limit);
  }

  Future<void> clearAuditEvents() async {
    final storage = _storage;
    if (storage == null) return;
    await storage.clearAuditEvents();
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final d = DeviceInfoPlugin();
    try {
      final a = await d.androidInfo;
      return {
        'platform': 'android',
        'brand': a.brand,
        'model': a.model,
        'manufacturer': a.manufacturer,
        'sdk_int': a.version.sdkInt,
        'release': a.version.release,
      };
    } catch (_) {}
    try {
      final i = await d.iosInfo;
      return {
        'platform': 'ios',
        'model': i.model,
        'name': i.name,
        'system_name': i.systemName,
        'system_version': i.systemVersion,
      };
    } catch (_) {}
    return {'platform': 'unknown'};
  }

  Future<String> _collectAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final b = info.buildNumber.trim();
      return b.isEmpty ? info.version : '${info.version}+$b';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<Map<String, dynamic>> _getLocationSnapshot() async {
    final now = DateTime.now();
    if (_lastLocation != null) {
      final hasCoords = _lastLocation!['lat'] != null && _lastLocation!['lng'] != null;
      final maxAge = hasCoords ? const Duration(minutes: 3) : const Duration(seconds: 20);
      if (now.difference(_lastLocationAt) < maxAge) {
        return _lastLocation!;
      }
    }
    final status = <String, dynamic>{
      'enabled': false,
      'permission': 'unknown',
      'lat': null,
      'lng': null,
      'accuracy': null,
    };
    // 避免 iOS 启动早期因定位插件调用导致潜在原生崩溃。
    if (Platform.isIOS) {
      status['permission'] = 'deferred_on_ios';
      _lastLocation = status;
      _lastLocationAt = now;
      return status;
    }
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      status['enabled'] = enabled;
      if (!enabled) {
        _lastLocation = status;
        _lastLocationAt = now;
        return status;
      }
      final p = await Geolocator.checkPermission();
      status['permission'] = p.name;
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) {
        _lastLocation = status;
        _lastLocationAt = now;
        return status;
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos != null) {
        status['lat'] = pos.latitude;
        status['lng'] = pos.longitude;
        status['accuracy'] = pos.accuracy;
      }
    } catch (_) {}
    _lastLocation = status;
    _lastLocationAt = now;
    return status;
  }
}

class AuditNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name ?? route.runtimeType.toString();
    AuditService.instance.setCurrentRoute(name);
    unawaited(AuditService.instance.logEvent(
      category: 'navigation',
      action: 'route_push',
      feature: name,
      extra: {
        'from': previousRoute?.settings.name ?? '',
      },
    ));
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final backTo = previousRoute?.settings.name ?? previousRoute?.runtimeType.toString() ?? '';
    AuditService.instance.setCurrentRoute(backTo);
    unawaited(AuditService.instance.logEvent(
      category: 'navigation',
      action: 'route_pop',
      feature: route.settings.name ?? route.runtimeType.toString(),
      extra: {'to': backTo},
    ));
    super.didPop(route, previousRoute);
  }
}
