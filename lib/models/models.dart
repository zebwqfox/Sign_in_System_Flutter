class Student {
  Student({required this.id, required this.studentId, required this.name});

  final int id;
  final String studentId;
  final String name;

  factory Student.fromJson(Map<String, dynamic> j) {
    return Student(
      id: (j['id'] as num).toInt(),
      studentId: j['student_id'] as String,
      name: j['name'] as String,
    );
  }
}

/// 与后端 `records` 表及前端点名流程字段一致。
class AttendanceRecord {
  AttendanceRecord({
    this.id,
    required this.studentId,
    required this.studentName,
    required this.status,
    this.reason = '',
  });

  int? id;
  final String studentId;
  final String studentName;
  String status;
  String reason;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'student_name': studentName,
        'status': status,
        'reason': reason,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) {
    return AttendanceRecord(
      id: j['id'] != null ? (j['id'] as num).toInt() : null,
      studentId: j['student_id'] as String,
      studentName: j['student_name'] as String,
      status: j['status'] as String,
      reason: (j['reason'] as String?) ?? '',
    );
  }

  AttendanceRecord copy() => AttendanceRecord(
        id: id,
        studentId: studentId,
        studentName: studentName,
        status: status,
        reason: reason,
      );
}

class SessionRow {
  SessionRow({
    required this.id,
    required this.sessionName,
    required this.createdAt,
    required this.totalStudents,
    required this.attendanceRate,
    this.isLocal = false,
    this.isPending = false,
  });

  final String id;
  final String sessionName;
  final String createdAt;
  final int totalStudents;
  final double attendanceRate;
  final bool isLocal;
  final bool isPending;

  factory SessionRow.fromServerJson(Map<String, dynamic> j) {
    return SessionRow(
      id: '${(j['id'] as num).toInt()}',
      sessionName: j['session_name'] as String,
      createdAt: j['created_at'] as String,
      totalStudents: (j['total_students'] as num?)?.toInt() ?? 0,
      attendanceRate: (j['attendance_rate'] as num?)?.toDouble() ?? 0,
    );
  }

  factory SessionRow.fromLocalPending(Map<String, dynamic> j) {
    return SessionRow(
      id: j['id'] as String,
      sessionName: j['session_name'] as String,
      createdAt: j['created_at'] as String,
      totalStudents: (j['total_students'] as num?)?.toInt() ?? 0,
      attendanceRate: (j['attendance_rate'] as num?)?.toDouble() ?? 0,
      isLocal: true,
      isPending: true,
    );
  }
}

class LocalPendingSession {
  LocalPendingSession({
    required this.id,
    required this.sessionName,
    required this.records,
    required this.createdAt,
    required this.totalStudents,
    required this.attendanceRate,
    this.syncAttempts = 0,
  });

  final String id;
  final String sessionName;
  final List<AttendanceRecord> records;
  final String createdAt;
  final int totalStudents;
  final double attendanceRate;
  int syncAttempts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_name': sessionName,
        'records': records.map((e) => e.toJson()).toList(),
        'created_at': createdAt,
        'total_students': totalStudents,
        'attendance_rate': attendanceRate,
        'isLocal': true,
        'syncAttempts': syncAttempts,
      };

  factory LocalPendingSession.fromJson(Map<String, dynamic> j) {
    final raw = j['records'] as List<dynamic>? ?? [];
    return LocalPendingSession(
      id: j['id'] as String,
      sessionName: j['session_name'] as String,
      records: raw
          .map((e) => AttendanceRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: j['created_at'] as String,
      totalStudents: (j['total_students'] as num?)?.toInt() ?? 0,
      attendanceRate: (j['attendance_rate'] as num?)?.toDouble() ?? 0,
      syncAttempts: (j['syncAttempts'] as num?)?.toInt() ?? 0,
    );
  }
}

class StatsRow {
  StatsRow({
    required this.studentId,
    required this.studentName,
    required this.totalChecks,
    required this.presentCount,
    required this.lateCount,
    required this.leaveCount,
    required this.leaveBCount,
    required this.leaveSCount,
    required this.absentCount,
  });

  final String studentId;
  final String studentName;
  final int totalChecks;
  final int presentCount;
  final int lateCount;
  final int leaveCount;
  final int leaveBCount;
  final int leaveSCount;
  final int absentCount;

  int get rate =>
      totalChecks == 0 ? 0 : (((presentCount + lateCount) / totalChecks) * 100).round();

  factory StatsRow.fromJson(Map<String, dynamic> j) {
    return StatsRow(
      studentId: j['student_id'] as String,
      studentName: j['student_name'] as String,
      totalChecks: (j['total_checks'] as num?)?.toInt() ?? 0,
      presentCount: (j['present_count'] as num?)?.toInt() ?? 0,
      lateCount: (j['late_count'] as num?)?.toInt() ?? 0,
      leaveCount: (j['leave_count'] as num?)?.toInt() ?? 0,
      leaveBCount: (j['leave_b_count'] as num?)?.toInt() ?? 0,
      leaveSCount: (j['leave_s_count'] as num?)?.toInt() ?? 0,
      absentCount: (j['absent_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class LogEntry {
  LogEntry({
    required this.id,
    required this.action,
    required this.ip,
    required this.location,
    required this.createdAt,
  });

  final int id;
  final String action;
  final String ip;
  final String location;
  final String createdAt;

  factory LogEntry.fromJson(Map<String, dynamic> j) {
    return LogEntry(
      id: (j['id'] as num).toInt(),
      action: j['action'] as String,
      ip: j['ip'] as String,
      location: j['location'] as String,
      createdAt: j['created_at'] as String,
    );
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
