import 'package:flutter/services.dart';

import 'storage_service.dart';

class CourseScheduleItem {
  CourseScheduleItem({
    required this.displayName,
    required this.summary,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.firstDateMs,
    this.untilDateMs,
    this.location,
    this.weekStart,
    this.weekEnd,
  });

  final String displayName;
  final String summary;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final int firstDateMs;
  final int? untilDateMs;
  final String? location;
  final int? weekStart;
  final int? weekEnd;

  String? get weekRangeLabel {
    if (weekStart == null || weekEnd == null) return null;
    return '第$weekStart-$weekEnd周';
  }

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'summary': summary,
        'weekday': weekday,
        'start_minute': startMinute,
        'end_minute': endMinute,
        'first_date_ms': firstDateMs,
        'until_date_ms': untilDateMs,
        'location': location ?? '',
        'week_start': weekStart,
        'week_end': weekEnd,
      };

  factory CourseScheduleItem.fromJson(Map<String, dynamic> j) {
    return CourseScheduleItem(
      displayName: (j['display_name'] ?? '').toString(),
      summary: (j['summary'] ?? '').toString(),
      weekday: (j['weekday'] as num?)?.toInt() ?? 1,
      startMinute: (j['start_minute'] as num?)?.toInt() ?? 0,
      endMinute: (j['end_minute'] as num?)?.toInt() ?? 0,
      firstDateMs: (j['first_date_ms'] as num?)?.toInt() ?? 0,
      untilDateMs: (j['until_date_ms'] as num?)?.toInt(),
      location: (j['location'] ?? '').toString(),
      weekStart: (j['week_start'] as num?)?.toInt(),
      weekEnd: (j['week_end'] as num?)?.toInt(),
    );
  }
}

class CourseScheduleService {
  CourseScheduleService._();

  static final CourseScheduleService instance = CourseScheduleService._();

  Future<List<CourseScheduleItem>> loadSchedule(StorageService storage) async {
    final saved = storage.getCourseSchedule();
    if (saved.isNotEmpty) {
      return saved.map(CourseScheduleItem.fromJson).toList();
    }
    return _loadFallbackFromAsset();
  }

  Future<int> importFromIcsText(StorageService storage, String icsText) async {
    final parsed = _parseIcs(icsText);
    await storage.setCourseSchedule(parsed.map((e) => e.toJson()).toList());
    return parsed.length;
  }

  Future<void> clearImportedSchedule(StorageService storage) async {
    await storage.clearCourseSchedule();
  }

  Future<String?> matchCourseNameNow(StorageService storage, DateTime now) async {
    final events = await loadSchedule(storage);
    if (events.isEmpty) return null;
    _Candidate? best;
    for (final item in events) {
      final c = _candidate(item, now);
      if (c == null) continue;
      if (best == null || c.score < best.score) best = c;
    }
    return best?.item.displayName;
  }

  Future<List<CourseScheduleItem>> _loadFallbackFromAsset() async {
    try {
      final raw = await rootBundle.loadString('class.ics');
      return _parseIcs(raw);
    } catch (_) {
      return const [];
    }
  }

  List<CourseScheduleItem> _parseIcs(String raw) {
    final text = raw.replaceAll('\r\n', '\n');
    final blocks = RegExp(r'BEGIN:VEVENT([\s\S]*?)END:VEVENT').allMatches(text);
    final out = <CourseScheduleItem>[];
    for (final m in blocks) {
      final block = m.group(1) ?? '';
      final summary = _field(block, 'SUMMARY')?.trim();
      final startRaw = _field(block, 'DTSTART');
      final endRaw = _field(block, 'DTEND');
      if (summary == null || summary.isEmpty || startRaw == null || endRaw == null) continue;
      final start = DateTime.tryParse(startRaw);
      final end = DateTime.tryParse(endRaw);
      if (start == null || end == null) continue;
      final startLocal = start.toLocal();
      final endLocal = end.toLocal();
      final firstDate = DateTime(startLocal.year, startLocal.month, startLocal.day);
      final untilDate = _parseUntilDate(_field(block, 'RRULE'));
      final description = _field(block, 'DESCRIPTION') ?? '';
      final location = (_field(block, 'LOCATION') ?? '').trim();
      final period = _parsePeriod(description);
      final weekRange = _parseWeekRange(description);
      final label = period == null
          ? summary
          : '第${period.$1}-${period.$2}节 $summary';
      out.add(CourseScheduleItem(
        displayName: label,
        summary: summary,
        weekday: startLocal.weekday,
        startMinute: startLocal.hour * 60 + startLocal.minute,
        endMinute: endLocal.hour * 60 + endLocal.minute,
        firstDateMs: firstDate.millisecondsSinceEpoch,
        untilDateMs: untilDate?.millisecondsSinceEpoch,
        location: location,
        weekStart: weekRange?.$1,
        weekEnd: weekRange?.$2,
      ));
    }
    out.sort((a, b) {
      final w = a.weekday.compareTo(b.weekday);
      if (w != 0) return w;
      return a.startMinute.compareTo(b.startMinute);
    });
    return out;
  }

  static String? _field(String block, String key) {
    final reg = RegExp('^$key(?:;[^:]+)?:\\s*(.+)\$', multiLine: true);
    return reg.firstMatch(block)?.group(1);
  }

  static (int, int)? _parsePeriod(String description) {
    final m = RegExp(r'第\s*(\d+)\s*-\s*(\d+)节').firstMatch(description);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  static (int, int)? _parseWeekRange(String description) {
    final m = RegExp(r'第\s*(\d+)\s*-\s*(\d+)周').firstMatch(description);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  static DateTime? _parseUntilDate(String? rrule) {
    if (rrule == null || rrule.isEmpty) return null;
    final m = RegExp(r'UNTIL=([0-9TZ]+)').firstMatch(rrule);
    if (m == null) return null;
    final raw = m.group(1)!;
    if (raw.length == 8) {
      final y = int.tryParse(raw.substring(0, 4));
      final mo = int.tryParse(raw.substring(4, 6));
      final d = int.tryParse(raw.substring(6, 8));
      if (y == null || mo == null || d == null) return null;
      return DateTime(y, mo, d);
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static _Candidate? _candidate(CourseScheduleItem item, DateTime now) {
    if (item.weekday != now.weekday) return null;
    final d = DateTime(now.year, now.month, now.day);
    final first = DateTime.fromMillisecondsSinceEpoch(item.firstDateMs);
    final firstDate = DateTime(first.year, first.month, first.day);
    if (d.isBefore(firstDate)) return null;
    if (item.untilDateMs != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(item.untilDateMs!);
      final untilDate = DateTime(until.year, until.month, until.day);
      if (d.isAfter(untilDate)) return null;
    }
    final nowMin = now.hour * 60 + now.minute;
    final inRange = nowMin >= item.startMinute - 20 && nowMin <= item.endMinute + 10;
    if (inRange) return _Candidate(item: item, score: 0);
    final diff = (nowMin - item.startMinute).abs();
    if (diff <= 120) {
      return _Candidate(item: item, score: diff + 100);
    }
    return null;
  }
}

class _Candidate {
  _Candidate({required this.item, required this.score});
  final CourseScheduleItem item;
  final int score;
}
