import 'package:intl/intl.dart';

class StudyDateUtils {
  StudyDateUtils._();

  /// 4AM 경계가 적용된 오늘 날짜 키 (yyyy-MM-dd)
  /// 새벽 0시~3시59분은 전날로 처리
  static String todayKey([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final effective = dt.hour < 4 ? dt.subtract(const Duration(days: 1)) : dt;
    return DateFormat('yyyy-MM-dd').format(effective);
  }

  /// 4AM 경계가 적용된 DateTime 반환
  static DateTime effectiveDate([DateTime? now]) {
    final dt = now ?? DateTime.now();
    return dt.hour < 4 ? dt.subtract(const Duration(days: 1)) : dt;
  }
}
