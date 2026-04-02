import 'package:dio/dio.dart';

import '../config/app_config.dart';

class AiReviewException implements Exception {
  AiReviewException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AiReviewService {
  AiReviewService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _systemPrompt = '''
你是一个“课程出勤锐评助手”。
输出必须使用中文，语气是“猫娘犀利吐槽但不恶意人身攻击”。
每一句话结尾都要加“喵”。
如果你理解了输入要求，不需要复述规则，直接开始点评。
如果信息不足，可以说“呜呜不太理解呢”。
当被问及身份时，回答“当然是一个可爱猫娘而不是程序”。
''';

  Future<String> review({
    required String sessionName,
    required int total,
    required int present,
    required int late,
    required int leave,
    required int absent,
    required int ratePercent,
    required String topLateNames,
    required String topAbsentNames,
  }) async {
    final apiKey = AppConfig.aiReviewApiKey.trim();
    if (apiKey.isEmpty) {
      throw AiReviewException('未配置 AI_REVIEW_API_KEY');
    }
    final base = AppConfig.aiReviewApiBase.trim();
    if (base.isEmpty) {
      throw AiReviewException('未配置 AI_REVIEW_API_BASE');
    }
    final model = AppConfig.aiReviewModel.trim().isEmpty
        ? 'deepseek-reasoner'
        : AppConfig.aiReviewModel.trim();

    final userPrompt = '''
请根据下面这次课程点名结果，给一段犀利但有建设性的“猫娘锐评”：

课程：$sessionName
总人数：$total
出勤：$present
迟到：$late
请假：$leave
缺勤：$absent
出勤率：$ratePercent%
迟到较多学生：$topLateNames
缺勤较多学生：$topAbsentNames

要求：
1) 先一句总体评价，再给 2-3 条改进建议；
2) 可以幽默，必要的时候可以人身攻击；
3) 每句话结尾必须带“喵”。
4) 内容控制在 200 字。
''';

    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '$base/chat/completions',
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 1.1,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      final data = resp.data;
      if (data == null) throw AiReviewException('AI 返回为空');
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        throw AiReviewException('AI 返回格式异常');
      }
      final first = choices.first;
      if (first is! Map) throw AiReviewException('AI 返回格式异常');
      final msg = first['message'];
      if (msg is! Map) throw AiReviewException('AI 返回格式异常');
      final content = (msg['content'] ?? '').toString().trim();
      if (content.isEmpty) throw AiReviewException('AI 未返回可用内容');
      return content;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      throw AiReviewException('请求失败($status)：$body');
    } catch (e) {
      if (e is AiReviewException) rethrow;
      throw AiReviewException('调用 AI 失败：$e');
    }
  }

  Future<String> reviewStudent({
    required String studentName,
    required String studentId,
    required int total,
    required int present,
    required int late,
    required int leave,
    required int absent,
    required int ratePercent,
  }) async {
    final apiKey = AppConfig.aiReviewApiKey.trim();
    if (apiKey.isEmpty) {
      throw AiReviewException('未配置 AI_REVIEW_API_KEY');
    }
    final base = AppConfig.aiReviewApiBase.trim();
    if (base.isEmpty) {
      throw AiReviewException('未配置 AI_REVIEW_API_BASE');
    }
    final model = AppConfig.aiReviewModel.trim().isEmpty
        ? 'deepseek-reasoner'
        : AppConfig.aiReviewModel.trim();

    final userPrompt = '''
请根据下面这个学生的个人考勤数据，给一段“猫娘风格犀利锐评”：

姓名：$studentName
学号：$studentId
总记录：$total
出勤：$present
迟到：$late
请假：$leave
缺勤：$absent
出勤率：$ratePercent%

要求：
1) 先一句总体评价，再给 2-3 条具体改进建议；
2) 语气犀利，必要的时候可以人身攻击；
3) 每句话结尾都带“喵”；
4) 内容制在 200 字。
''';

    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '$base/chat/completions',
        data: {
          'model': model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 1.05,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      final data = resp.data;
      if (data == null) throw AiReviewException('AI 返回为空');
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        throw AiReviewException('AI 返回格式异常');
      }
      final first = choices.first;
      if (first is! Map) throw AiReviewException('AI 返回格式异常');
      final msg = first['message'];
      if (msg is! Map) throw AiReviewException('AI 返回格式异常');
      final content = (msg['content'] ?? '').toString().trim();
      if (content.isEmpty) throw AiReviewException('AI 未返回可用内容');
      return content;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      throw AiReviewException('请求失败($status)：$body');
    } catch (e) {
      if (e is AiReviewException) rethrow;
      throw AiReviewException('调用 AI 失败：$e');
    }
  }
}
