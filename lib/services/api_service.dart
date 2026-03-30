import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../models/models.dart';
import 'storage_service.dart';

/// 使用 Dio + Cookie，并携带与浏览器一致的请求头。
///
/// 后端 [requireAuth]：除 `/api/login`、`/api/health`、公开分享接口外，须在请求头携带
/// `x-auth-token`（值即登录接口返回的 `data.sessionId`）。
class ApiService {
  ApiService({
    required String baseUrl,
    StorageService? authStorage,
  })  : _apiBase = _normalizeApiBase(baseUrl),
        _origin = _computeOrigin(baseUrl),
        _authStorage = authStorage {
    _jar = CookieJar();
    _dio = Dio(
      BaseOptions(
        baseUrl: _apiBase,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: _browserHeaders(_origin),
        validateStatus: (code) => code != null && code < 600,
      ),
    );
    _dio.interceptors.add(CookieManager(_jar));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _hydrateTokenFromStorageIfNeeded();
          if (_shouldSendAuthToken(options.uri) && _authToken != null && _authToken!.isNotEmpty) {
            options.headers['x-auth-token'] = _authToken;
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (response.statusCode == 401 &&
              response.requestOptions.uri.toString().isNotEmpty &&
              _shouldSendAuthToken(response.requestOptions.uri)) {
            _onUnauthorized?.call();
          }
          return handler.next(response);
        },
      ),
    );
  }

  final String _apiBase;
  final String? _origin;
  final StorageService? _authStorage;
  late final Dio _dio;
  late final CookieJar _jar;
  String? _authToken;
  void Function()? _onUnauthorized;

  /// 登录成功后传入后端返回的 sessionId；退出登录传 `null`。
  void setAuthToken(String? sessionId) {
    _authToken = sessionId;
  }

  void setOnUnauthorized(void Function()? cb) {
    _onUnauthorized = cb;
  }

  void _hydrateTokenFromStorageIfNeeded() {
    final st = _authStorage;
    if (st == null) return;
    if (_authToken != null && _authToken!.isNotEmpty) return;
    if (!st.isLoggedIn) return;
    final sid = st.authSessionId;
    if (sid != null && sid.isNotEmpty) _authToken = sid;
  }

  /// 用完整 URL 判断，避免 Dio 在部分情况下 [Uri.path] 未含 `/api` 导致遗漏 token。
  static bool _shouldSendAuthToken(Uri uri) {
    final s = uri.toString();
    if (!s.contains('/api/')) return false;
    if (s.contains('/api/login')) return false;
    if (s.contains('/api/health')) return false;
    if (s.contains('/share/session_detail')) return false;
    return true;
  }

  static String _normalizeApiBase(String baseUrl) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  static String? _computeOrigin(String apiBase) {
    try {
      final u = Uri.parse(apiBase.trim());
      if (!u.hasScheme || u.host.isEmpty) return null;
      final defaultPort = (u.scheme == 'https') ? 443 : 80;
      final port = (u.hasPort && u.port != defaultPort) ? ':${u.port}' : '';
      return '${u.scheme}://${u.host}$port';
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _browserHeaders(String? origin) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      if (origin != null) ...{
        'Origin': origin,
        'Referer': '$origin/',
      },
    };
  }

  /// 在登录或拉取数据前调用：访问 `https://域名/`，收集边缘层下发的 Cookie。
  Future<void> warmupEdgeSession() async {
    final o = _origin;
    if (o == null) return;
    try {
      await _dio.get<dynamic>(
        '$o/',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          headers: {
            ..._browserHeaders(o),
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );
    } catch (_) {
      // 首页不可达时仍继续尝试 API（内网调试等）
    }
  }

  dynamic _asJson(Response<dynamic> res) {
    final d = res.data;
    if (d == null) return null;
    if (d is Map || d is List) return d;
    if (d is String) {
      if (d.isEmpty) return null;
      return jsonDecode(d);
    }
    return d;
  }

  void _throwIfHttpError(Response<dynamic> res, dynamic data) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;
    String msg = '请求失败';
    if (data is Map) {
      if (data['message'] != null) {
        msg = '${data['message']}';
      } else if (data['error'] != null) {
        msg = '${data['error']}';
      }
    } else {
      msg = 'HTTP $code';
    }
    throw ApiException(msg, statusCode: code);
  }

  void _throwIfBusinessFalse(dynamic data) {
    if (data is Map && data['success'] == false) {
      final msg = '${data['error'] ?? data['message'] ?? '请求失败'}';
      throw ApiException(msg);
    }
  }

  /// 登录成功返回 `sessionId`，用于后续请求的 `x-auth-token`。
  Future<String> login(String password, {Map<String, dynamic>? deviceInfo}) async {
    final body = <String, dynamic>{'password': password};
    if (deviceInfo != null) body['deviceInfo'] = deviceInfo;
    final res = await _dio.post<dynamic>('/login', data: body);
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
    if (data is Map && data['data'] is Map) {
      final sid = (data['data'] as Map)['sessionId'];
      if (sid is String && sid.isNotEmpty) return sid;
      if (sid is num) return sid.toString();
    }
    throw ApiException('登录响应缺少 sessionId');
  }

  Future<List<Student>> fetchStudents() async {
    final res = await _dio.get<dynamic>('/students');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    final list = (data is Map ? data['data'] : null) as List<dynamic>? ?? [];
    return list.map((e) => Student.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> importStudents(List<Map<String, dynamic>> students) async {
    final res = await _dio.post<dynamic>('/import', data: {'students': students});
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
  }

  Future<void> updateStudent(int id, String name, String studentId) async {
    final res = await _dio.put<dynamic>('/students/$id', data: {'name': name, 'student_id': studentId});
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
  }

  Future<void> deleteStudent(int id) async {
    final res = await _dio.delete<dynamic>('/students/$id');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
  }

  Future<void> batchDeleteStudents(List<int> ids) async {
    final res = await _dio.post<dynamic>('/students/batch_delete', data: {'ids': ids});
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
  }

  Future<int> submitSession({
    required String sessionName,
    required List<AttendanceRecord> records,
    required String createdAtIso,
  }) async {
    final payload = {
      'session_name': sessionName,
      'records': records
          .map((r) => {
                'student_id': r.studentId,
                'student_name': r.studentName,
                'status': r.status,
                'reason': r.reason,
              })
          .toList(),
      'created_at': createdAtIso,
    };
    final res = await _dio.post<dynamic>('/submit_session', data: payload);
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    if (data is Map && data['message'] == 'Saved' && data['sessionId'] != null) {
      return (data['sessionId'] as num).toInt();
    }
    throw ApiException('Unexpected response');
  }

  Future<List<SessionRow>> fetchHistorySessions() async {
    final res = await _dio.get<dynamic>('/history_sessions');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    final list = (data is Map ? data['data'] : null) as List<dynamic>? ?? [];
    return list.map((e) => SessionRow.fromServerJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<({List<AttendanceRecord> records, Map<String, dynamic> session})> fetchSessionDetail(int id) async {
    final res = await _dio.get<dynamic>('/session_detail/$id');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    if (data is! Map) throw ApiException('Invalid detail');
    final recs = (data['data'] as List<dynamic>? ?? [])
        .map((e) => AttendanceRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final session = Map<String, dynamic>.from(data['session'] as Map);
    return (records: recs, session: session);
  }

  /// 分享页公开接口，无需 `x-auth-token`（与后端 `/api/share/session_detail/:id` 一致）。
  Future<({List<AttendanceRecord> records, Map<String, dynamic> session})> fetchShareSessionDetail(int id) async {
    final res = await _dio.get<dynamic>('/share/session_detail/$id');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    if (data is! Map) throw ApiException('Invalid detail');
    final recs = (data['data'] as List<dynamic>? ?? [])
        .map((e) => AttendanceRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final session = Map<String, dynamic>.from(data['session'] as Map);
    return (records: recs, session: session);
  }

  Future<void> deleteSession(int id) async {
    final res = await _dio.delete<dynamic>('/sessions/$id');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
  }

  Future<void> updateSessionName(int id, String name) async {
    final res = await _dio.put<dynamic>('/sessions/$id', data: {'session_name': name});
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
  }

  Future<double> updateRecord({required int recordId, required String status, required String reason}) async {
    final res = await _dio.put<dynamic>('/records/$recordId', data: {'status': status, 'reason': reason});
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    _throwIfBusinessFalse(data);
    if (data is Map && data['data'] != null && data['data'] is Map) {
      final dr = data['data'] as Map;
      if (dr['newRate'] != null) return (dr['newRate'] as num).toDouble();
    }
    return 0;
  }

  Future<List<StatsRow>> fetchStats() async {
    final res = await _dio.get<dynamic>('/stats');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    final list = (data is Map ? data['data'] : null) as List<dynamic>? ?? [];
    return list.map((e) => StatsRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<List<Map<String, dynamic>>> fetchStudentRecords(String studentId) async {
    final enc = Uri.encodeComponent(studentId);
    final res = await _dio.get<dynamic>('/students/$enc/records');
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    final list = (data is Map ? data['data'] : null) as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<LogEntry>> fetchLogs({int limit = 100}) async {
    final res = await _dio.get<dynamic>('/logs', queryParameters: {'limit': limit});
    final data = _asJson(res);
    _throwIfHttpError(res, data);
    final list = (data is Map ? data['data'] : null) as List<dynamic>? ?? [];
    return list.map((e) => LogEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}
