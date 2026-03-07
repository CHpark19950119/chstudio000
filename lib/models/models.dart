/// CHEONHONG STUDIO — Firestore 데이터 모델
/// v8.5: NFC 4태그 토글 + 이동시간 + 수면관리

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─── 시간 기록 (기상/공부시작/외출/귀가/공부종료) ───
class TimeRecord {
  final String date;
  final String? wake;
  final String? study;        // 공부시작 (NFC study 태그 첫 터치)
  final String? studyEnd;     // 공부종료 (NFC study 태그 두번째 터치)
  final String? outing;       // 외출 (NFC outing 태그 첫 터치)
  final String? returnHome;   // 귀가 (NFC outing 태그 두번째 터치)
  final String? arrival;      // GPS 도착 감지
  final String? bedTime;      // 수면시간 (NFC sleep 태그)
  final String? mealStart;   // [레거시] 단일 식사 — 하위호환용
  final String? mealEnd;     // [레거시] 단일 식사 — 하위호환용
  final List<MealEntry> meals; // ★ v9: 다회 식사 기록
  final bool noOuting; // ★ v10: 외출 안하는 날 (재택)

  TimeRecord({
    required this.date,
    this.wake,
    this.study,
    this.studyEnd,
    this.outing,
    this.returnHome,
    this.arrival,
    this.bedTime,
    this.mealStart,
    this.mealEnd,
    List<MealEntry>? meals,
    this.noOuting = false,
  }) : meals = meals ?? [];

  factory TimeRecord.fromMap(String date, Map<String, dynamic> map) {
    // 레거시 단일 필드 읽기
    final legacyStart = map['mealStart'] as String?;
    final legacyEnd = map['mealEnd'] as String?;

    // 다회 meals 배열 읽기
    List<MealEntry> mealList = [];
    if (map['meals'] is List) {
      mealList = (map['meals'] as List)
          .map((e) => MealEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    // 레거시→신규 마이그레이션: meals가 비어있고 레거시 필드 있으면 변환
    if (mealList.isEmpty && legacyStart != null) {
      mealList = [MealEntry(start: legacyStart, end: legacyEnd)];
    }

    return TimeRecord(
      date: date,
      wake: map['wake'] as String?,
      study: map['study'] as String?,
      studyEnd: map['studyEnd'] as String?,
      outing: map['outing'] as String?,
      returnHome: map['returnHome'] as String?,
      arrival: map['arrival'] as String?,
      bedTime: map['bedTime'] as String?,
      mealStart: legacyStart,
      mealEnd: legacyEnd,
      meals: mealList,
      noOuting: map['noOuting'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{};
    if (wake != null) m['wake'] = wake;
    if (study != null) m['study'] = study;
    if (studyEnd != null) m['studyEnd'] = studyEnd;
    if (outing != null) m['outing'] = outing;
    if (returnHome != null) m['returnHome'] = returnHome;
    if (arrival != null) m['arrival'] = arrival;
    if (bedTime != null) m['bedTime'] = bedTime;
    // ★ 레거시 필드도 유지 (웹앱 호환)
    if (mealStart != null) m['mealStart'] = mealStart;
    if (mealEnd != null) m['mealEnd'] = mealEnd;
    // ★ 신규 다회 식사
    if (meals.isNotEmpty) {
      m['meals'] = meals.map((e) => e.toMap()).toList();
    }
    if (noOuting) m['noOuting'] = true;
    return m;
  }

  /// 첫 번째 식사의 시작/종료 (레거시 호환)
  String? get firstMealStart => meals.isNotEmpty ? meals.first.start : mealStart;
  String? get firstMealEnd => meals.isNotEmpty ? meals.first.end : mealEnd;

  /// 진행 중인 식사 (end가 null)
  MealEntry? get activeMeal {
    try { return meals.firstWhere((m) => m.end == null); } catch (_) { return null; }
  }

  /// 총 식사시간 (분)
  int get totalMealMinutes => meals.fold(0, (sum, m) => sum + (m.durationMin ?? 0));

  /// 식사시간 (분) — 레거시 호환
  int? get mealMinutes {
    if (meals.isNotEmpty) return totalMealMinutes > 0 ? totalMealMinutes : null;
    if (mealStart == null || mealEnd == null) return null;
    return _timeDiffMin(mealStart!, mealEnd!);
  }

  String? get mealFormatted {
    final m = mealMinutes;
    if (m == null) return null;
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }

  /// meals 보존 복사 헬퍼
  TimeRecord copyWith({
    String? wake, String? study, String? studyEnd,
    String? outing, String? returnHome, String? arrival,
    String? bedTime, String? mealStart, String? mealEnd,
    List<MealEntry>? meals, bool? noOuting,
    bool clearWake = false, bool clearStudy = false, bool clearStudyEnd = false,
    bool clearOuting = false, bool clearReturnHome = false,
    bool clearBedTime = false,
  }) {
    return TimeRecord(
      date: date,
      wake: clearWake ? null : (wake ?? this.wake),
      study: clearStudy ? null : (study ?? this.study),
      studyEnd: clearStudyEnd ? null : (studyEnd ?? this.studyEnd),
      outing: clearOuting ? null : (outing ?? this.outing),
      returnHome: clearReturnHome ? null : (returnHome ?? this.returnHome),
      arrival: arrival ?? this.arrival,
      bedTime: clearBedTime ? null : (bedTime ?? this.bedTime),
      mealStart: mealStart ?? this.mealStart,
      mealEnd: mealEnd ?? this.mealEnd,
      meals: meals ?? this.meals,
      noOuting: noOuting ?? this.noOuting,
    );
  }

  /// 등교 이동시간 (분): 공부시작 - 외출
  int? get commuteToMinutes {
    if (outing == null || study == null) return null;
    return _timeDiffMin(outing!, study!);
  }

  /// 하교 이동시간 (분): 귀가 - 공부종료
  int? get commuteFromMinutes {
    if (studyEnd == null || returnHome == null) return null;
    return _timeDiffMin(studyEnd!, returnHome!);
  }

  /// 학교 체류시간 (분): 공부종료 - 공부시작
  int? get stayMinutes {
    if (study == null || studyEnd == null) return null;
    return _timeDiffMin(study!, studyEnd!);
  }

  /// 총 외출시간 (분): 귀가 - 외출
  int? get outingMinutes {
    if (outing == null || returnHome == null) return null;
    return _timeDiffMin(outing!, returnHome!);
  }

  /// 외출시간 포맷 (예: "2h 30m")
  String? get outingFormatted {
    final min = outingMinutes;
    if (min == null || min <= 0) return null;
    final h = min ~/ 60;
    final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  static int? _timeDiffMin(String from, String to) {
    try {
      final fp = from.split(':');
      final tp = to.split(':');
      final fm = int.parse(fp[0]) * 60 + int.parse(fp[1]);
      final tm = int.parse(tp[0]) * 60 + int.parse(tp[1]);
      int diff = tm - fm;
      // ★ FIX: 자정 넘김 처리 (예: 23:00→00:30 = 90분)
      if (diff < 0) diff += 1440;
      // 12시간 이상이면 비정상 (역전된 기록)
      return diff <= 720 ? diff : null;
    } catch (_) {
      return null;
    }
  }
}

// ─── 식사 기록 엔트리 (v9: 다회 식사) ───
class MealEntry {
  final String start;     // HH:mm
  final String? end;      // HH:mm (null이면 식사 중)
  final String? type;     // breakfast, lunch, dinner, snack

  MealEntry({required this.start, this.end, this.type});

  factory MealEntry.fromMap(Map<String, dynamic> m) => MealEntry(
    start: m['start'] ?? '',
    end: m['end'] as String?,
    type: m['type'] as String?,
  );

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'start': start};
    if (end != null) m['end'] = end;
    if (type != null) m['type'] = type;
    return m;
  }

  int? get durationMin {
    if (end == null) return null;
    try {
      final sp = start.split(':');
      final ep = end!.split(':');
      final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      int diff = em - sm;
      if (diff < 0) diff += 1440;
      return diff <= 720 ? diff : null;
    } catch (_) { return null; }
  }

  String? get durationFormatted {
    final m = durationMin;
    if (m == null) return null;
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }

  MealEntry withEnd(String endTime) => MealEntry(start: start, end: endTime, type: type);
}

// ─── 학습시간 기록 (일별) ───
class StudyTimeRecord {
  final String date;
  final int totalMinutes;
  final int studyMinutes;
  final int lectureMinutes;
  final int effectiveMinutes;
  final bool finalized;

  StudyTimeRecord({
    required this.date,
    this.totalMinutes = 0,
    this.studyMinutes = 0,
    this.lectureMinutes = 0,
    this.effectiveMinutes = 0,
    this.finalized = false,
  });

  factory StudyTimeRecord.fromMap(String date, Map<String, dynamic> map) {
    return StudyTimeRecord(
      date: date,
      totalMinutes: map['totalMinutes'] ?? map['minutes'] ?? 0,
      studyMinutes: map['studyMinutes'] ?? 0,
      lectureMinutes: map['lectureMinutes'] ?? 0,
      effectiveMinutes: map['effectiveMinutes'] ?? map['minutes'] ?? 0,
      finalized: map['_finalized'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'totalMinutes': totalMinutes,
        'studyMinutes': studyMinutes,
        'lectureMinutes': lectureMinutes,
        'effectiveMinutes': effectiveMinutes,
        '_finalized': finalized,
      };
}

// ─── 포커스 세션 세그먼트 ───
class FocusSegment {
  final String startTime;
  final String endTime;
  final String subject;
  final String mode;
  final int durationMin;

  FocusSegment({
    required this.startTime,
    required this.endTime,
    required this.subject,
    required this.mode,
    required this.durationMin,
  });

  factory FocusSegment.fromMap(Map<String, dynamic> map) {
    return FocusSegment(
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      subject: map['subject'] ?? '',
      mode: map['mode'] ?? 'study',
      durationMin: map['durationMin'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'startTime': startTime,
        'endTime': endTime,
        'subject': subject,
        'mode': mode,
        'durationMin': durationMin,
      };
}

// ─── 포커스 사이클 ───
class FocusCycle {
  final String id;
  final String date;
  final String startTime;
  final String? endTime;
  final String subject;
  final List<FocusSegment> segments;
  final int studyMin;
  final int lectureMin;
  final int effectiveMin;
  final int restMin;

  FocusCycle({
    required this.id,
    required this.date,
    required this.startTime,
    this.endTime,
    required this.subject,
    this.segments = const [],
    this.studyMin = 0,
    this.lectureMin = 0,
    this.effectiveMin = 0,
    this.restMin = 0,
  });

  factory FocusCycle.fromMap(Map<String, dynamic> map) {
    return FocusCycle(
      id: map['id'] ?? '',
      date: map['date'] ?? '',
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'],
      subject: map['subject'] ?? '',
      segments: (map['segments'] as List<dynamic>?)
              ?.map((s) => FocusSegment.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      studyMin: map['studyMin'] ?? 0,
      lectureMin: map['lectureMin'] ?? 0,
      effectiveMin: map['effectiveMin'] ?? 0,
      restMin: map['restMin'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
        'subject': subject,
        'segments': segments.map((s) => s.toMap()).toList(),
        'studyMin': studyMin,
        'lectureMin': lectureMin,
        'effectiveMin': effectiveMin,
        'restMin': restMin,
      };
}

// ─── 알람 설정 ───
class AlarmSettings {
  final String targetWakeTime;
  final bool enabled;
  final List<int> activeDays;
  final int snoozeMinutes;
  final String ringtone;
  final bool vibrate;
  final bool qrWakeEnabled;
  final String qrSecret;
  final bool nfcWakeEnabled;

  AlarmSettings({
    this.targetWakeTime = '07:00',
    this.enabled = true,
    this.activeDays = const [1, 2, 3, 4, 5, 6],
    this.snoozeMinutes = 5,
    this.ringtone = 'default',
    this.vibrate = true,
    this.qrWakeEnabled = false,
    this.qrSecret = 'CHEONHONG_WAKE_VERIFY_2026',
    this.nfcWakeEnabled = false,
  });

  factory AlarmSettings.fromMap(Map<String, dynamic> map) {
    return AlarmSettings(
      targetWakeTime: map['targetWakeTime'] ?? '07:00',
      enabled: map['enabled'] ?? true,
      activeDays: List<int>.from(map['activeDays'] ?? [1, 2, 3, 4, 5, 6]),
      snoozeMinutes: map['snoozeMinutes'] ?? 5,
      ringtone: map['ringtone'] ?? 'default',
      vibrate: map['vibrate'] ?? true,
      qrWakeEnabled: map['qrWakeEnabled'] ?? false,
      qrSecret: map['qrSecret'] ?? 'CHEONHONG_WAKE_VERIFY_2026',
      nfcWakeEnabled: map['nfcWakeEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'targetWakeTime': targetWakeTime,
        'enabled': enabled,
        'activeDays': activeDays,
        'snoozeMinutes': snoozeMinutes,
        'ringtone': ringtone,
        'vibrate': vibrate,
        'qrWakeEnabled': qrWakeEnabled,
        'qrSecret': qrSecret,
        'nfcWakeEnabled': nfcWakeEnabled,
      };
}

// ─── 집중모드 설정 ───
class FocusModeConfig {
  final bool enabled;
  final List<String> blockedPackages;
  final bool enableDnd;
  final bool showOverlay;

  FocusModeConfig({
    this.enabled = false,
    this.blockedPackages = const [],
    this.enableDnd = true,
    this.showOverlay = true,
  });

  factory FocusModeConfig.fromMap(Map<String, dynamic> map) {
    return FocusModeConfig(
      enabled: map['enabled'] ?? false,
      blockedPackages: List<String>.from(map['blockedPackages'] ?? []),
      enableDnd: map['enableDnd'] ?? true,
      showOverlay: map['showOverlay'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'blockedPackages': blockedPackages,
        'enableDnd': enableDnd,
        'showOverlay': showOverlay,
      };
}

// ─── 앱 사용 통계 ───
class AppUsageStat {
  final String date;
  final String packageName;
  final String appName;
  final int usageMinutes;
  final String category;

  AppUsageStat({
    required this.date,
    required this.packageName,
    required this.appName,
    required this.usageMinutes,
    this.category = 'other',
  });

  Map<String, dynamic> toMap() => {
        'date': date,
        'packageName': packageName,
        'appName': appName,
        'usageMinutes': usageMinutes,
        'category': category,
      };
}

// ─── 데일리 그레이딩 (v8.0) ───
class DailyGrade {
  final String date;
  final double wakeScore;
  final double studyStartScore;
  final double studyTimeScore;
  final double totalScore;
  final String grade;

  DailyGrade({
    required this.date,
    required this.wakeScore,
    required this.studyStartScore,
    required this.studyTimeScore,
    required this.totalScore,
    required this.grade,
  });

  factory DailyGrade.calculate({
    required String date,
    String? wakeTime,
    String? studyStartTime,
    int effectiveMinutes = 0,
  }) {
    double wakeScore = 25.0;
    if (wakeTime != null) {
      final parts = wakeTime.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final totalMin = h * 60 + m;
      const target = 7 * 60;      // 07:00
      const floor = 10 * 60;      // 10:00
      const range = floor - target; // 180분
      if (totalMin <= target) {
        wakeScore = 25.0; // 07:00 이전 = 만점
      } else if (totalMin < floor) {
        // 07:00~10:00: 부드러운 감점 (이차함수 커브)
        final ratio = (totalMin - target) / range; // 0.0 ~ 1.0
        wakeScore = (25.0 * (1.0 - ratio * ratio)).clamp(0, 25);
      } else {
        wakeScore = 0; // 10:00 이후 = 0점
      }
    } else {
      wakeScore = 0;
    }

    double studyStartScore = 25.0;
    if (studyStartTime != null) {
      final parts = studyStartTime.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final totalMin = h * 60 + m;
      if (totalMin <= 600) {
        studyStartScore = 25.0;
      } else if (totalMin <= 660) {
        studyStartScore = 25.0 - (totalMin - 600) * 0.25;
      } else if (totalMin <= 720) {
        studyStartScore = (25.0 - 60 * 0.25) - (totalMin - 660) * 0.083;
      } else {
        studyStartScore = 0;
      }
      studyStartScore = studyStartScore.clamp(0, 25);
    } else {
      studyStartScore = 0;
    }

    double studyTimeScore = (effectiveMinutes / 480.0 * 50.0).clamp(0, 50);
    double total = wakeScore + studyStartScore + studyTimeScore;

    String grade;
    if (total >= 95) {
      grade = 'S+';
    } else if (total >= 90) {
      grade = 'S';
    } else if (total >= 80) {
      grade = 'A';
    } else if (total >= 70) {
      grade = 'B';
    } else if (total >= 60) {
      grade = 'C';
    } else if (total >= 40) {
      grade = 'D';
    } else {
      grade = 'F';
    }

    return DailyGrade(
      date: date,
      wakeScore: wakeScore,
      studyStartScore: studyStartScore,
      studyTimeScore: studyTimeScore,
      totalScore: total,
      grade: grade,
    );
  }
}

// ══════════════════════════════════════════
//  위치 상태 모델
// ══════════════════════════════════════════

enum LocationState {
  idle,
  preparing,
  traveling,
  staying,
  returning,
}

enum MotionState {
  stationary,
  moving,
  unknown,
}

class NearbyPlaceResult {
  final String name;
  final String? vicinity;
  final double lat;
  final double lng;
  final List<String> types;

  NearbyPlaceResult({
    required this.name,
    this.vicinity,
    required this.lat,
    required this.lng,
    this.types = const [],
  });

  factory NearbyPlaceResult.fromJson(Map<String, dynamic> json) {
    final loc = json['geometry']?['location'] ?? {};
    return NearbyPlaceResult(
      name: json['name'] ?? '',
      vicinity: json['vicinity'],
      lat: (loc['lat'] ?? 0).toDouble(),
      lng: (loc['lng'] ?? 0).toDouble(),
      types: List<String>.from(json['types'] ?? []),
    );
  }

  String get guessedCategory {
    if (types.any((t) => t.contains('library'))) return 'library';
    if (types.any((t) => t.contains('cafe') || t.contains('coffee'))) return 'cafe';
    if (types.any((t) => t.contains('school') || t.contains('university'))) return 'school';
    if (types.any((t) => t.contains('office') || t.contains('company'))) return 'work';
    return 'other';
  }
}

// ─── 위치 기록 ───
class LocationRecord {
  final String id;
  final String date;
  final String timestamp;
  final double latitude;
  final double longitude;
  final String? placeName;
  final String? placeId;
  final String? placeCategory;
  final String? wifiSsid;
  final int durationMinutes;

  LocationRecord({
    required this.id,
    required this.date,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.placeId,
    this.placeCategory,
    this.wifiSsid,
    this.durationMinutes = 0,
  });

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'] ?? '',
      date: map['date'] ?? '',
      timestamp: map['timestamp'] ?? '',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      placeName: map['placeName'],
      placeId: map['placeId'],
      placeCategory: map['placeCategory'],
      wifiSsid: map['wifiSsid'],
      durationMinutes: map['durationMinutes'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
        'placeName': placeName,
        'placeId': placeId,
        'placeCategory': placeCategory,
        'wifiSsid': wifiSsid,
        'durationMinutes': durationMinutes,
      };
}

// ─── 등록 장소 (지오펜스) ───
class KnownPlace {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final String? wifiSsid;
  final bool autoStudyStart;

  KnownPlace({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100,
    this.wifiSsid,
    this.autoStudyStart = false,
  });

  factory KnownPlace.fromMap(Map<String, dynamic> map) {
    return KnownPlace(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      emoji: map['emoji'] ?? '📍',
      category: map['category'] ?? 'other',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      radiusMeters: map['radiusMeters'] ?? 100,
      wifiSsid: map['wifiSsid'],
      autoStudyStart: map['autoStudyStart'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'wifiSsid': wifiSsid,
        'autoStudyStart': autoStudyStart,
      };

  static String categoryEmoji(String cat) {
    switch (cat) {
      case 'home': return '🏠';
      case 'library': return '📚';
      case 'cafe': return '☕';
      case 'school': return '🏫';
      case 'work': return '💼';
      case 'restaurant': return '🍽️';
      default: return '📍';
    }
  }

  static String categoryLabel(String cat) {
    switch (cat) {
      case 'home': return '집';
      case 'library': return '도서관';
      case 'cafe': return '카페';
      case 'school': return '학교/학원';
      case 'work': return '직장';
      case 'restaurant': return '음식점';
      default: return '기타';
    }
  }
}

// ─── 행동 타임라인 ───
class BehaviorTimelineEntry {
  final String id;
  final String date;
  final String startTime;
  final String endTime;
  final String type;
  final String label;
  final String? emoji;
  final String? placeName;
  final int durationMinutes;
  final Map<String, dynamic>? meta;

  BehaviorTimelineEntry({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.label,
    this.emoji,
    this.placeName,
    required this.durationMinutes,
    this.meta,
  });

  factory BehaviorTimelineEntry.fromMap(Map<String, dynamic> map) {
    return BehaviorTimelineEntry(
      id: map['id'] ?? '',
      date: map['date'] ?? '',
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      type: map['type'] ?? '',
      label: map['label'] ?? '',
      emoji: map['emoji'],
      placeName: map['placeName'],
      durationMinutes: map['durationMinutes'] ?? 0,
      meta: map['meta'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
        'type': type,
        'label': label,
        'emoji': emoji,
        'placeName': placeName,
        'durationMinutes': durationMinutes,
        'meta': meta,
      };
}

// ─── 과목 설정 ───
class SubjectConfig {
  static const Map<String, SubjectInfo> _factoryDefaults = {
    '자료해석': SubjectInfo('자료해석', '📊', 0xFF6366F1),
    '언어논리': SubjectInfo('언어논리', '📝', 0xFF10B981),
    '상황판단': SubjectInfo('상황판단', '🧩', 0xFFF59E0B),
  };

  static Map<String, SubjectInfo> _subjects = {};
  static bool _loaded = false;

  static Map<String, SubjectInfo> get subjects {
    if (!_loaded) return _factoryDefaults;
    return Map.unmodifiable(_subjects);
  }

  /// 첫 실행 시 기본값, 이후엔 저장된 목록 사용
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('subject_list_v2');
      if (raw != null) {
        final list = List<dynamic>.from(jsonDecode(raw));
        _subjects = {};
        for (final item in list) {
          final m = Map<String, dynamic>.from(item);
          final name = m['name'] ?? '';
          if (name.isEmpty) continue;
          _subjects[name] = SubjectInfo(name, m['emoji'] ?? '📚', m['color'] ?? 0xFF6366F1);
        }
      } else {
        // 최초 실행 — 기본값 복사
        _subjects = Map.from(_factoryDefaults);
        await _save();
      }
    } catch (_) {
      _subjects = Map.from(_factoryDefaults);
    }
    _loaded = true;
  }

  static Future<void> addSubject(String name, String emoji, int colorValue) async {
    _subjects[name] = SubjectInfo(name, emoji, colorValue);
    await _save();
  }

  static Future<void> removeSubject(String name) async {
    _subjects.remove(name);
    await _save();
  }

  static Future<void> updateSubject(String oldName, String newName, String emoji, int colorValue) async {
    if (oldName != newName) _subjects.remove(oldName);
    _subjects[newName] = SubjectInfo(newName, emoji, colorValue);
    await _save();
  }

  /// 기본 과목 전체 복원
  static Future<void> resetToDefaults() async {
    _subjects = Map.from(_factoryDefaults);
    await _save();
  }

  static Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = _subjects.values.map((s) => {
        'name': s.name, 'emoji': s.emoji, 'color': s.colorValue,
      }).toList();
      await p.setString('subject_list_v2', jsonEncode(list));
    } catch (_) {}
  }
}

class SubjectInfo {
  final String name;
  final String emoji;
  final int colorValue;
  const SubjectInfo(this.name, this.emoji, this.colorValue);
}

// ══════════════════════════════════════════
//  v8.5: NFC 태그 모델 (4태그 토글 시스템)
// ══════════════════════════════════════════

/// NFC 태그 역할 — 4종
enum NfcTagRole {
  wake,     // 욕실 → 기상시간
  ready,    // 책상 → 음성 브리핑만
  outing,   // 현관 → 토글: 외출 ↔ 귀가
  study,    // 독서대 → 토글: 공부시작 ↔ 공부종료
  sleep,    // 침대 → 취침시간 기록
  meal,     // 식탁 → 토글: 식사시작 ↔ 식사종료
}

class NfcTagConfig {
  final String id;
  final String name;
  final NfcTagRole role;
  final String? nfcId;
  final String createdAt;

  NfcTagConfig({
    required this.id,
    required this.name,
    required this.role,
    this.nfcId,
    required this.createdAt,
  });

  factory NfcTagConfig.fromMap(Map<String, dynamic> map) {
    return NfcTagConfig(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      role: NfcTagRole.values.firstWhere(
        (r) => r.name == (map['role'] ?? 'wake'),
        orElse: () => NfcTagRole.wake,
      ),
      nfcId: map['nfcId'],
      createdAt: map['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'role': role.name,
        'nfcId': nfcId,
        'createdAt': createdAt,
      };

  String get emoji {
    switch (role) {
      case NfcTagRole.wake: return '🚿';
      case NfcTagRole.ready: return '📖';
      case NfcTagRole.outing: return '🚪';
      case NfcTagRole.study: return '📚';
      case NfcTagRole.sleep: return '🛏️';
      case NfcTagRole.meal: return '🍽️';
    }
  }

  String get roleLabel {
    switch (role) {
      case NfcTagRole.wake: return '기상 인증';
      case NfcTagRole.ready: return '준비 완료 + 브리핑';
      case NfcTagRole.outing: return '외출 ↔ 귀가 (토글)';
      case NfcTagRole.study: return '공부시작 ↔ 공부종료 (토글)';
      case NfcTagRole.sleep: return '수면시작';
      case NfcTagRole.meal: return '식사시작 ↔ 식사종료 (토글)';
    }
  }

  static String roleDescription(NfcTagRole role) {
    switch (role) {
      case NfcTagRole.wake: return '욕실 NFC → 기상시간 기록';
      case NfcTagRole.ready: return '책상 NFC → 음성 브리핑';
      case NfcTagRole.outing: return '현관 NFC → 외출/귀가 토글 + GPS';
      case NfcTagRole.study: return '독서대 NFC → 공부시작/종료 토글';
      case NfcTagRole.sleep: return '침대 NFC → 취침시간 기록';
      case NfcTagRole.meal: return '식탁 NFC → 식사시작/종료 토글';
    }
  }
}

/// NFC 스캔 이벤트 기록
class NfcEvent {
  final String id;
  final String date;
  final String timestamp;
  final NfcTagRole role;
  final String tagName;
  final String? action; // 토글: 'start'/'end' 구분

  NfcEvent({
    required this.id,
    required this.date,
    required this.timestamp,
    required this.role,
    required this.tagName,
    this.action,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'timestamp': timestamp,
        'role': role.name,
        'tagName': tagName,
        'action': action,
      };
}

// ══════════════════════════════════════════
//  v8.5: 수면 관리 모델 (#32~38)
// ══════════════════════════════════════════

/// 수면 설정
class SleepSettings {
  final String targetBedTime;    // 목표 취침 시간 (예: "23:30")
  final bool enabled;
  final bool appLockEnabled;     // #33: 야간 앱 잠금
  final bool screenMonitor;      // #34: 화면 켜짐 감지
  final List<String> allowedApps; // 잠금 시 허용 앱
  final int warningMinBefore;    // 취침 몇 분 전 예고 (기본 30)

  SleepSettings({
    this.targetBedTime = '23:30',
    this.enabled = true,
    this.appLockEnabled = false,
    this.screenMonitor = false,
    this.allowedApps = const [
      'com.kakao.talk',           // 카카오톡 (통화)
      'com.samsung.android.dialer', // 전화
      'com.samsung.android.messaging', // 문자
    ],
    this.warningMinBefore = 30,
  });

  factory SleepSettings.fromMap(Map<String, dynamic> map) {
    return SleepSettings(
      targetBedTime: map['targetBedTime'] ?? '23:30',
      enabled: map['enabled'] ?? true,
      appLockEnabled: map['appLockEnabled'] ?? false,
      screenMonitor: map['screenMonitor'] ?? false,
      allowedApps: List<String>.from(map['allowedApps'] ?? [
        'com.kakao.talk',
        'com.samsung.android.dialer',
        'com.samsung.android.messaging',
      ]),
      warningMinBefore: map['warningMinBefore'] ?? 30,
    );
  }

  Map<String, dynamic> toMap() => {
        'targetBedTime': targetBedTime,
        'enabled': enabled,
        'appLockEnabled': appLockEnabled,
        'screenMonitor': screenMonitor,
        'allowedApps': allowedApps,
        'warningMinBefore': warningMinBefore,
      };
}

/// 수면 기록 (일별)
class SleepRecord {
  final String date;
  final String? bedTime;         // 실제 취침 시간
  final String? wakeTime;        // 기상 시간
  final int? sleepMinutes;       // 수면 시간 (분)
  final int screenOnCount;       // #34: 수면 중 화면 켜짐 횟수
  final int screenOnMinutes;     // 수면 중 화면 켜진 총 시간 (분)

  SleepRecord({
    required this.date,
    this.bedTime,
    this.wakeTime,
    this.sleepMinutes,
    this.screenOnCount = 0,
    this.screenOnMinutes = 0,
  });

  factory SleepRecord.fromMap(String date, Map<String, dynamic> map) {
    return SleepRecord(
      date: date,
      bedTime: map['bedTime'] as String?,
      wakeTime: map['wakeTime'] as String?,
      sleepMinutes: map['sleepMinutes'] as int?,
      screenOnCount: map['screenOnCount'] ?? 0,
      screenOnMinutes: map['screenOnMinutes'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'bedTime': bedTime,
        'wakeTime': wakeTime,
        'sleepMinutes': sleepMinutes,
        'screenOnCount': screenOnCount,
        'screenOnMinutes': screenOnMinutes,
      };
}

/// #35: 수면 스코어 (100점)
class SleepGrade {
  final String date;
  final double bedTimeScore;     // 25점 (목표 시간 준수)
  final double wakeTimeScore;    // 25점 (목표 기상)
  final double durationScore;    // 25점 (7~8시간 적정)
  final double phoneScore;       // 25점 (화면 이탈 감점)
  final double totalScore;
  final String grade;

  SleepGrade({
    required this.date,
    required this.bedTimeScore,
    required this.wakeTimeScore,
    required this.durationScore,
    required this.phoneScore,
    required this.totalScore,
    required this.grade,
  });

  factory SleepGrade.calculate({
    required String date,
    SleepSettings? settings,
    SleepRecord? record,
    String? targetWakeTime,
  }) {
    final targetBed = settings?.targetBedTime ?? '23:30';

    // 취침 점수 (25점)
    double bedScore = 0;
    if (record?.bedTime != null) {
      final diff = _absTimeDiff(record!.bedTime!, targetBed);
      bedScore = (25.0 - diff * 0.5).clamp(0, 25); // 분당 0.5점 감점
    }

    // 기상 점수 (25점)
    double wakeScore = 0;
    if (record?.wakeTime != null) {
      final tw = targetWakeTime ?? '07:00';
      final diff = _absTimeDiff(record!.wakeTime!, tw);
      wakeScore = (25.0 - diff / 4.0).clamp(0, 25); // 4분당 1점 감점
    }

    // 수면시간 점수 (25점) — 7~8시간이 만점
    double durScore = 0;
    if (record?.sleepMinutes != null) {
      final sm = record!.sleepMinutes!;
      if (sm >= 420 && sm <= 480) {
        durScore = 25;
      } else if (sm >= 360 && sm < 420) {
        durScore = 25.0 - (420 - sm) / 4.0;
      } else if (sm > 480 && sm <= 540) {
        durScore = 25.0 - (sm - 480) / 4.0;
      } else {
        durScore = (25.0 - ((sm - 450).abs() / 3.0)).clamp(0, 25);
      }
    }

    // 폰 이탈 점수 (25점)
    double phoneScore = 25;
    if (record != null) {
      // 화면 켜짐 횟수당 3점 감점, 최대 10점
      phoneScore -= (record.screenOnCount * 3.0).clamp(0, 10);
      // 화면 켜진 시간 분당 1.5점 감점
      phoneScore -= (record.screenOnMinutes * 1.5).clamp(0, 15);
      phoneScore = phoneScore.clamp(0, 25);
    }

    final total = bedScore + wakeScore + durScore + phoneScore;

    String grade;
    if (total >= 95) grade = 'S+';
    else if (total >= 90) grade = 'S';
    else if (total >= 80) grade = 'A';
    else if (total >= 70) grade = 'B';
    else if (total >= 60) grade = 'C';
    else if (total >= 40) grade = 'D';
    else grade = 'F';

    return SleepGrade(
      date: date,
      bedTimeScore: bedScore,
      wakeTimeScore: wakeScore,
      durationScore: durScore,
      phoneScore: phoneScore,
      totalScore: total,
      grade: grade,
    );
  }

  static double _absTimeDiff(String time1, String time2) {
    try {
      final p1 = time1.split(':');
      final p2 = time2.split(':');
      final m1 = int.parse(p1[0]) * 60 + int.parse(p1[1]);
      final m2 = int.parse(p2[0]) * 60 + int.parse(p2[1]);
      final diff = (m1 - m2).abs();
      // ★ FIX: 자정 넘김 — 720분(12시간) 이상이면 반대편이 더 가까움
      return diff > 720 ? (1440 - diff).toDouble() : diff.toDouble();
    } catch (_) {
      return 0;
    }
  }
}

// ══════════════════════════════════════════
//  날씨 데이터 (#44)
// ══════════════════════════════════════════

class WeatherData {
  final double temp;
  final double feelsLike;
  final double tempMin;
  final double tempMax;
  final int humidity;
  final String description;
  final String icon;
  final String main;
  final double windSpeed;
  final DateTime fetchedAt;

  WeatherData({
    required this.temp,
    required this.feelsLike,
    required this.tempMin,
    required this.tempMax,
    required this.humidity,
    required this.description,
    required this.icon,
    required this.main,
    required this.windSpeed,
    required this.fetchedAt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final weather = (json['weather'] as List).first;
    final main = json['main'] as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>;
    return WeatherData(
      temp: (main['temp'] as num).toDouble(),
      feelsLike: (main['feels_like'] as num).toDouble(),
      tempMin: (main['temp_min'] as num).toDouble(),
      tempMax: (main['temp_max'] as num).toDouble(),
      humidity: main['humidity'] as int,
      description: weather['description'] as String,
      icon: weather['icon'] as String,
      main: weather['main'] as String,
      windSpeed: (wind['speed'] as num).toDouble(),
      fetchedAt: DateTime.now(),
    );
  }

  String get emoji {
    switch (main.toLowerCase()) {
      case 'clear': return '☀️';
      case 'clouds': return '☁️';
      case 'rain': case 'drizzle': return '🌧️';
      case 'thunderstorm': return '⛈️';
      case 'snow': return '❄️';
      case 'mist': case 'fog': case 'haze': return '🌫️';
      default: return '🌤️';
    }
  }

  String get briefingSummary {
    final t = temp.round();
    final fl = feelsLike.round();
    final hi = tempMax.round();
    final lo = tempMin.round();
    return '현재 $t도, 체감 $fl도. 최고 $hi도 최저 $lo도. $description. 습도 $humidity%.';
  }
}
// ═══════════════════════════════════════════════════════════
// F2: 메모 모델
// ═══════════════════════════════════════════════════════════

class Memo {
  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime? reminderAt;
  final bool pinned;
  final bool completed;
  final String? category; // study, daily, important

  Memo({
    required this.id,
    required this.content,
    required this.createdAt,
    this.reminderAt,
    this.pinned = false,
    this.completed = false,
    this.category,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
    'pinned': pinned,
    'completed': completed,
    if (category != null) 'category': category,
  };

  factory Memo.fromMap(Map<String, dynamic> m) => Memo(
    id: m['id'] ?? '',
    content: m['content'] ?? '',
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    reminderAt: m['reminderAt'] != null ? DateTime.tryParse(m['reminderAt']) : null,
    pinned: m['pinned'] ?? false,
    completed: m['completed'] ?? false,
    category: m['category'] as String?,
  );

  Memo copyWith({
    String? content,
    DateTime? reminderAt,
    bool? pinned,
    bool? completed,
    String? category,
    bool clearReminder = false,
  }) => Memo(
    id: id,
    content: content ?? this.content,
    createdAt: createdAt,
    reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
    pinned: pinned ?? this.pinned,
    completed: completed ?? this.completed,
    category: category ?? this.category,
  );

  static String categoryEmoji(String? cat) {
    switch (cat) {
      case 'study': return '📚';
      case 'important': return '⚡';
      case 'daily': return '📝';
      default: return '💡';
    }
  }

  static String categoryLabel(String? cat) {
    switch (cat) {
      case 'study': return '학습';
      case 'important': return '중요';
      case 'daily': return '일상';
      default: return '기타';
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 3순위: 학습 진행도 모델 (웹앱 progressGoals 호환)
// ═══════════════════════════════════════════════════════════

class ProgressGoal {
  final String id;
  final String subject;
  final String title;
  final int totalUnits;
  final String unitName; // '강' or 'p'
  final String goalType; // 'lecture' or 'textbook'
  final int startPage;
  final int endPage;
  int currentUnit;
  bool completed;
  String? startDate;
  String? endDate;
  List<ProgressLog> dailyLogs;
  List<CompletionRecord> completionHistory;
  String? lastLogDate;
  String? completedAt;
  int? completedRound;
  String? groupId;
  String? groupName;
  final String createdAt;

  ProgressGoal({
    required this.id,
    required this.subject,
    required this.title,
    required this.totalUnits,
    this.unitName = '강',
    this.goalType = 'lecture',
    this.startPage = 0,
    this.endPage = 0,
    this.currentUnit = 0,
    this.completed = false,
    this.startDate,
    this.endDate,
    List<ProgressLog>? dailyLogs,
    List<CompletionRecord>? completionHistory,
    this.lastLogDate,
    this.completedAt,
    this.completedRound,
    this.groupId,
    this.groupName,
    String? createdAt,
  })  : dailyLogs = dailyLogs ?? [],
        completionHistory = completionHistory ?? [],
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  double get progressPercent =>
      totalUnits > 0 ? (currentUnit / totalUnits * 100).clamp(0, 100) : 0;

  bool get isOverdue =>
      endDate != null &&
      !completed &&
      DateTime.tryParse(endDate!)?.isBefore(DateTime.now()) == true;

  int get overdueDays {
    if (!isOverdue || endDate == null) return 0;
    return DateTime.now().difference(DateTime.parse(endDate!)).inDays;
  }

  int get totalStudyMinutes =>
      dailyLogs.fold(0, (sum, log) => sum + (log.studyMinutes ?? 0));

  String get totalStudyFormatted {
    final h = totalStudyMinutes ~/ 60;
    final m = totalStudyMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  factory ProgressGoal.fromMap(Map<String, dynamic> m) {
    return ProgressGoal(
      id: m['id'] ?? 'goal_${DateTime.now().millisecondsSinceEpoch}',
      subject: m['subject'] ?? '기타',
      title: m['title'] ?? '',
      totalUnits: (m['totalUnits'] as num?)?.toInt() ?? 0,
      unitName: m['unitName'] ?? '강',
      goalType: m['goalType'] ?? 'lecture',
      startPage: (m['startPage'] as num?)?.toInt() ?? 0,
      endPage: (m['endPage'] as num?)?.toInt() ?? 0,
      currentUnit: (m['currentUnit'] as num?)?.toInt() ?? 0,
      completed: m['completed'] ?? false,
      startDate: m['startDate'] as String?,
      endDate: m['endDate'] as String?,
      dailyLogs: (m['dailyLogs'] as List<dynamic>?)
              ?.map((e) =>
                  ProgressLog.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      completionHistory: (m['completionHistory'] as List<dynamic>?)
              ?.map((e) => CompletionRecord.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      lastLogDate: m['lastLogDate'] as String?,
      completedAt: m['completedAt'] as String?,
      completedRound: (m['completedRound'] as num?)?.toInt(),
      groupId: m['groupId'] as String?,
      groupName: m['groupName'] as String?,
      createdAt: m['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'subject': subject,
        'title': title,
        'totalUnits': totalUnits,
        'unitName': unitName,
        'goalType': goalType,
        'startPage': startPage,
        'endPage': endPage,
        'currentUnit': currentUnit,
        'completed': completed,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        'dailyLogs': dailyLogs.map((l) => l.toMap()).toList(),
        'completionHistory':
            completionHistory.map((c) => c.toMap()).toList(),
        if (lastLogDate != null) 'lastLogDate': lastLogDate,
        if (completedAt != null) 'completedAt': completedAt,
        if (completedRound != null) 'completedRound': completedRound,
        if (groupId != null) 'groupId': groupId,
        if (groupName != null) 'groupName': groupName,
        'createdAt': createdAt,
      };

  static String subjectEmoji(String subject) {
    switch (subject) {
      case '자료해석': return '📊';
      case '언어논리': return '📝';
      case '상황판단': return '🧩';
      case '헌법': return '⚖️';
      case '영어': return '🌐';
      default: return '📚';
    }
  }

  static const subjectColors = {
    '자료해석': 0xFF34547A,
    '언어논리': 0xFF8B575C,
    '상황판단': 0xFF2D5A4C,
    '헌법': 0xFF10B981,
    '영어': 0xFF0EA5E9,
  };
}

class ProgressLog {
  final String date;
  final int from;
  final int to;
  final int? studyMinutes;
  final String? loggedAt;

  ProgressLog({
    required this.date,
    required this.from,
    required this.to,
    this.studyMinutes,
    this.loggedAt,
  });

  factory ProgressLog.fromMap(Map<String, dynamic> m) => ProgressLog(
        date: m['date'] ?? '',
        from: (m['from'] as num?)?.toInt() ?? 0,
        to: (m['to'] as num?)?.toInt() ?? 0,
        studyMinutes: (m['studyMinutes'] as num?)?.toInt(),
        loggedAt: m['loggedAt'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'from': from,
        'to': to,
        if (studyMinutes != null) 'studyMinutes': studyMinutes,
        if (loggedAt != null) 'loggedAt': loggedAt,
      };
}

class CompletionRecord {
  final int round;
  final String completedAt;
  final String? startDate;
  final String? endDate;
  final int totalLogs;
  final int totalStudyMinutes;
  final int finalUnit;

  CompletionRecord({
    required this.round,
    required this.completedAt,
    this.startDate,
    this.endDate,
    this.totalLogs = 0,
    this.totalStudyMinutes = 0,
    this.finalUnit = 0,
  });

  factory CompletionRecord.fromMap(Map<String, dynamic> m) =>
      CompletionRecord(
        round: (m['round'] as num?)?.toInt() ?? 1,
        completedAt: m['completedAt'] ?? '',
        startDate: m['startDate'] as String?,
        endDate: m['endDate'] as String?,
        totalLogs: (m['totalLogs'] as num?)?.toInt() ?? 0,
        totalStudyMinutes: (m['totalStudyMinutes'] as num?)?.toInt() ?? 0,
        finalUnit: (m['finalUnit'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'round': round,
        'completedAt': completedAt,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        'totalLogs': totalLogs,
        'totalStudyMinutes': totalStudyMinutes,
        'finalUnit': finalUnit,
      };
}

// ═══════════════════════════════════════════
//  데일리 일기 (DailyDiary)
// ═══════════════════════════════════════════

class DailyDiary {
  final String date;
  final String content;
  final String? mood;
  final String updatedAt;

  DailyDiary({
    required this.date,
    required this.content,
    this.mood,
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  factory DailyDiary.fromMap(Map<String, dynamic> m) => DailyDiary(
    date: m['date'] ?? '',
    content: m['content'] ?? '',
    mood: m['mood'] as String?,
    updatedAt: m['updatedAt'] ?? '',
  );

  Map<String, dynamic> toMap() => {
    'date': date,
    'content': content,
    if (mood != null) 'mood': mood,
    'updatedAt': updatedAt,
  };
}