import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/botanical_theme.dart';
import '../services/alarm_service.dart';
import '../services/focus_service.dart';
import '../services/focus_mode_service.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../services/nfc_service.dart';
import '../services/weather_service.dart';
import '../services/briefing_service.dart';
import '../services/sleep_service.dart';
import '../services/ai_calendar_service.dart';
import '../services/telegram_service.dart';
import '../models/models.dart';
import 'alarm_settings_screen.dart';
import 'focus/focus_screen.dart';
import 'location_screen.dart';
import 'nfc/nfc_screen.dart' hide StatisticsScreen;
import 'qr_wake_screen.dart';
import 'settings_screen.dart';
import 'calendar_screen.dart';
import 'statistics_screen.dart';
import 'progress_screen.dart';
import 'painters.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'status_editor_sheet.dart';
import 'focus_records_widget.dart';
import 'insight_screen.dart';
import 'order/order_screen.dart';
import '../models/order_models.dart';
import '../models/plan_models.dart';
import '../services/todo_service.dart';
import '../services/exam_ticket_service.dart';
import '../services/local_cache_service.dart';
import '../services/creature_service.dart';
import '../utils/study_date_utils.dart';
import '../widgets/creature_float_button.dart';
import 'habitat_screen.dart';

part 'home_focus_section.dart';
part 'home_daily_log.dart';
part 'home_routine_card.dart';
part 'home_order_section.dart';
part 'home_todo_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _ft = FocusService();
  final _ls = LocationService();
  final _nfc = NfcService();
  final _weather = WeatherService();
  final _sleepSvc = SleepService();
  Timer? _ui;
  Timer? _streamDebounce;     // ★ stream listener 디바운스
  bool _isLoading = false;    // ★ _load() 동시 실행 방지
  bool _playedEntryAnim = false;
  String? _wake, _studyStart, _studyEnd;
  String? _outing, _returnHome;
  String? _bedTime;
  String? _mealStart, _mealEnd;
  int? _outingMinutes;
  int _effMin = 0;
  DailyGrade? _grade;
  AlarmSettings _alarm = AlarmSettings();
  String? _currentPlace;
  bool _locationTracking = false;
  WeatherData? _weatherData;
  SleepGrade? _lastSleepGrade;
  bool _noOuting = false; // ★ v10: 외출 안하는 날
  int _tab = 0;
  List<BehaviorTimelineEntry> _todayTimeline = [];
  List<MealEntry> _todayMeals = []; // ★ v9: 다회 식사
  List<String> _dailyMemos = [];   // ★ 데일리 메모

  // ★ Creature
  int _creatureLevel = 1;
  int _creatureStage = 0;

  // ★ R2: COMPASS 대시보드 데이터
  OrderData? _orderData;
  List<ExamTicketInfo> _examTickets = [];

  // ★ 오늘의 Todo
  TodoDaily? _todayTodos;
  Map<String, double>? _weeklyHistoryCache;
  late String _todoSelectedDate;  // 날짜 네비게이션용

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fbSub;
  int _retryDelay = 5; // ★ 스트림 재연결 지수 백오프 (초)

  late AnimationController _staggerController;
  final List<Animation<double>> _fadeAnims = [];
  final List<Animation<Offset>> _slideAnims = [];
  static const _cardCount = 6;

  // ★ 작업4: 모션 이펙트 컨트롤러
  late AnimationController _breathCtrl;   // A) Breathing Glow (3초)
  late AnimationController _particleCtrl; // B) Floating Particles (10초)
  late AnimationController _blobCtrl;     // C) Morphing Blob (8초)
  late AnimationController _shimmerCtrl;  // D) Shimmer Scan (2.5초)
  late AnimationController _pulseCtrl;    // F) Pulse Ring (2초)

  @override
  void initState() {
    super.initState();
    _todoSelectedDate = StudyDateUtils.todayKey();
    _staggerController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    for (int i = 0; i < _cardCount; i++) {
      final start = i * 0.12;
      final end = (start + 0.35).clamp(0.0, 1.0);
      _fadeAnims.add(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut)));
      _slideAnims.add(Tween<Offset>(
        begin: const Offset(0, 0.12), end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic))));
    }
    // ★ stagger 애니메이션: _load 완료와 무관하게 즉시 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_playedEntryAnim) {
        _playedEntryAnim = true;
        _staggerController.forward();
      }
    });
    _runStartup(); // ★ 역마이그레이션 → 스트림 → _load
    _checkPendingWake();
    _runMigration0223(); // 1회성 22일 기록 이관
    WeatherService().checkMorningWeatherAlert(); // ★ 아침 비/눈 Telegram 알림

    // ★ 작업4: 모션 이펙트 초기화
    _breathCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _blobCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

    _nfc.addListener(_onNfcChanged);
    _ui = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final isOut = _outing != null && _returnHome == null;
      if (_ft.isRunning || isOut) _safeSetState(() {});
    });
  }

  @override
  void dispose() {
    _ui?.cancel();
    _fbSub?.cancel();
    _streamDebounce?.cancel();
    _nfc.removeListener(_onNfcChanged);
    _staggerController.dispose();
    // ★ 모션 이펙트 dispose
    _breathCtrl.dispose();
    _particleCtrl.dispose();
    _blobCtrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onNfcChanged() {
    if (!mounted) return;
    _safeSetState(() {});
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isLoading) _load();
    });
  }

  void _startFirebaseListener() {
    _fbSub?.cancel();
    // ★ 단일 study 문서 스트림 — 모든 데이터가 여기에 있음
    _fbSub = FirebaseService().watchStudyData().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) return;
      _streamDebounce?.cancel();
      _streamDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;

        // ★ write 보호 중이면 스트림 데이터로 UI/캐시 갱신 스킵
        final isProtected = LocalCacheService().isWriteProtected();
        if (!isProtected) {
          FirebaseService().updateCacheFromStream(data);
        }
        final d = _studyDate();

        // ── timeRecords ──
        String? wake, study, studyEnd, outing, returnHome, bedTime, mealStart, mealEnd;
        List<MealEntry>? meals;
        bool? noOuting;
        int? outMin;
        bool hasTodayTimeRecord = false;
        try {
          final trRaw = data['timeRecords'] as Map<String, dynamic>?;
          if (trRaw != null && trRaw[d] != null) {
            hasTodayTimeRecord = true;
            final tr = TimeRecord.fromMap(d, trRaw[d] as Map<String, dynamic>);
            wake = tr.wake; study = tr.study; studyEnd = tr.studyEnd;
            outing = tr.outing; returnHome = tr.returnHome;
            bedTime = tr.bedTime;
            mealStart = tr.mealStart; mealEnd = tr.mealEnd;
            meals = tr.meals; noOuting = tr.noOuting; outMin = tr.outingMinutes;
          }
        } catch (e) { debugPrint('[Home] stream timeRecords: $e'); }

        // ── studyTimeRecords ──
        int? effMin;
        bool hasTodayStudyTime = false;
        try {
          final strRaw = data['studyTimeRecords'] as Map<String, dynamic>?;
          if (strRaw != null && strRaw[d] != null) {
            hasTodayStudyTime = true;
            effMin = StudyTimeRecord.fromMap(d, strRaw[d] as Map<String, dynamic>).effectiveMinutes;
          }
        } catch (e) { debugPrint('[Home] stream studyTimeRecords: $e'); }

        // ── orderData ──
        OrderData? orderData;
        try {
          final od = data['orderData'];
          if (od is Map && od.isNotEmpty) {
            orderData = OrderData.fromMap(Map<String, dynamic>.from(od));
          }
        } catch (e) { debugPrint('[Home] stream orderData: $e'); }

        // ── todos ──
        TodoDaily? todayTodos;
        try {
          final todosRaw = data['todos'];
          if (todosRaw is Map) {
            final todosMap = Map<String, dynamic>.from(todosRaw);
            if (todosMap[d] != null) {
              todayTodos = TodoDaily.fromMap(
                  Map<String, dynamic>.from(todosMap[d] as Map));
            }
          }
        } catch (e) { debugPrint('[Home] stream todos: $e'); }

        _safeSetState(() {
          // ★ write 보호 중이면 timeRecords도 스트림 덮어쓰기 차단 (공부종료 등 소실 방지)
          if (hasTodayTimeRecord && !isProtected) {
            _wake = wake; _studyStart = study; _studyEnd = studyEnd;
            _outing = outing; _returnHome = returnHome; _bedTime = bedTime;
            _mealStart = mealStart; _mealEnd = mealEnd;
            _todayMeals = meals ?? []; _noOuting = noOuting ?? false;
            _outingMinutes = outMin;
          }
          if (hasTodayStudyTime && effMin != null) _effMin = effMin;
          if (orderData != null && !isProtected) _orderData = orderData;
          // ★ write 보호 중이면 todos 덮어쓰기 스킵 (방금 입력한 데이터 보호)
          if (todayTodos != null && !isProtected) _todayTodos = todayTodos;
          _grade = DailyGrade.calculate(
            date: d, wakeTime: _wake,
            studyStartTime: _studyStart, effectiveMinutes: _effMin);
        });
      });
    }, onError: (e) {
      debugPrint('[Home] stream error: $e');
      _fbSub?.cancel();
      Future.delayed(Duration(seconds: _retryDelay), () {
        if (mounted) {
          _startFirebaseListener();
          _retryDelay = (_retryDelay * 2).clamp(5, 60);
        }
      });
    });
    _retryDelay = 5;
  }

  Future<void> _load() async {
    // NFC 리스너는 initState에서 등록됨 (ChangeNotifier 방식)
    if (_isLoading) return;
    _isLoading = true;
    try {
      await _doLoad(); // ★ 전체 타임아웃 제거 — 각 문서별 개별 타임아웃으로 처리
    } catch (e) {
      debugPrint('[Home] _load error: $e');
    } finally {
      _isLoading = false; // ★ 어떤 상황에서도 반드시 해제
    }
  }

  /// Todo 전용 경량 리로드 (todos 문서만 읽기)
  Future<void> _loadTodosOnly() async {
    // ★ write 보호 중이면 리로드 스킵 (방금 입력한 데이터 보호)
    if (LocalCacheService().isWriteProtected()) {
      debugPrint('[Home] _loadTodosOnly skip: write-protected');
      return;
    }
    try {
      final data = await FirebaseService().getTodosData();
      if (data == null || !mounted) return;
      // ★ 리로드 도중 write가 발생했으면 결과 무시
      if (LocalCacheService().isWriteProtected()) return;
      final d = _studyDate();
      final todosRaw = data['todos'] is Map ? Map<String, dynamic>.from(data['todos'] as Map) : null;
      TodoDaily? todos;
      if (todosRaw != null && todosRaw[d] != null) {
        todos = TodoDaily.fromMap(Map<String, dynamic>.from(todosRaw[d] as Map));
      }
      final history = <String, double>{};
      if (todosRaw != null) {
        final cutoff = DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(const Duration(days: 7)));
        for (final entry in todosRaw.entries) {
          if (entry.key.compareTo(cutoff) >= 0) {
            try {
              final td = TodoDaily.fromMap(Map<String, dynamic>.from(entry.value as Map));
              history[entry.key] = td.completionRate;
            } catch (_) {}
          }
        }
      }
      _safeSetState(() {
        _todayTodos = todos;
        _weeklyHistoryCache = history;
      });
    } catch (e) { debugPrint('[Home] _loadTodosOnly: $e'); }
  }

  /// 특정 날짜 Todo 로드 (날짜 네비게이션용)
  Future<void> _loadTodosForDate(String date) async {
    try {
      final todos = await TodoService().getTodos(date);
      _safeSetState(() {
        _todoSelectedDate = date;
        _todayTodos = todos ?? TodoDaily(date: date);
      });
    } catch (e) { debugPrint('[Home] _loadTodosForDate: $e'); }
  }

  /// Todo 아이템 수정 (제목 변경)
  void _editTodoItem(TodoItem item) async {
    final controller = TextEditingController(text: item.title);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final safeBottom = MediaQuery.of(ctx).padding.bottom;
        return Container(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: bottomInset + safeBottom + 16),
          decoration: BoxDecoration(
            color: _dk ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: _textMuted.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('할일 수정', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: _textMain)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '할일 제목',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12)),
              style: TextStyle(fontSize: 14, color: _textMain),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isNotEmpty) Navigator.pop(ctx, v);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: BotanicalColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('저장',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        );
      },
    );
    controller.dispose();
    if (result == null || result == item.title) return;

    // 제목 업데이트
    final todos = _todayTodos;
    if (todos == null) return;
    final updated = TodoDaily(
      date: todos.date,
      items: todos.items.map((t) =>
        t.id == item.id ? t.copyWith(title: result) : t).toList(),
      memo: todos.memo,
      createdAt: todos.createdAt,
    );
    _safeSetState(() => _todayTodos = updated);
    TodoService().saveTodos(updated);
  }

  Future<void> _doLoad() async {
    final d = _studyDate();
    final yesterday = DateFormat('yyyy-MM-dd').format(
        DateFormat('yyyy-MM-dd').parse(d).subtract(const Duration(days: 1)));
    final fb = FirebaseService();
    final lc = LocalCacheService();
    debugPrint('[Home] _doLoad 시작 (date=$d)');

    // ═══ 1단계: 로컬 today 캐시에서 즉시 표시 (0ms) ═══
    final localToday = lc.getGeneric('today');
    if (localToday != null) {
      _parseTodayData(localToday, d);
      _safeSetState(() {});
      debugPrint('[Home] today 캐시 즉시 표시 OK');
    } else {
      // fallback: 기존 study 캐시
      final localData = lc.getStudyData();
      if (localData != null) {
        _parseStudyData(localData, d);
        _safeSetState(() {});
        debugPrint('[Home] study 캐시 fallback 표시');
      }
    }

    // ═══ 2단계: Firebase today 문서 갱신 (1~2KB만 읽기) ═══
    _tryRefresh('today', () async {
      final data = await fb.getTodayDoc();
      if (data != null) {
        _parseTodayData(data, d);
        _safeSetState(() {});
        debugPrint('[Home] today 문서 갱신 OK');
      } else {
        // today 문서가 아직 없으면 study 문서 fallback
        final studyData = await fb.getStudyData();
        if (studyData != null) {
          _parseStudyData(studyData, d);
          _safeSetState(() {});
          debugPrint('[Home] study 문서 fallback OK');
        }
      }
    });

    // ═══ 3단계: 외부 서비스 (각각 독립, 실패 무관) ═══
    _tryRefresh('alarm', () async {
      _alarm = await fb.getAlarmSettings();
      _safeSetState(() {});
    });
    _tryRefresh('weather', () async {
      final w = await _weather.getCurrentWeather();
      if (w != null) _safeSetState(() => _weatherData = w);
    });
    _tryRefresh('sleep', () async {
      final s = await _sleepSvc.getSleepGrade(yesterday);
      if (s != null) _safeSetState(() => _lastSleepGrade = s);
    });
    _tryRefresh('timeline', () async {
      final t2 = await fb.getBehaviorTimeline(d);
      if (t2.isNotEmpty) _safeSetState(() => _todayTimeline = t2);
    });
    _tryRefresh('memos', () async {
      final m = await AiCalendarService().getMemosForDate(d);
      _safeSetState(() => _dailyMemos = m);
    });
    _tryRefresh('tickets', () async {
      final tk = await ExamTicketService().loadAllTickets();
      _safeSetState(() => _examTickets = tk);
    });
    _tryRefresh('location', () async {
      _safeSetState(() {
        _currentPlace = _ls.currentPlaceName;
        _locationTracking = _ls.isTracking;
      });
    });
    _tryRefresh('creature', () async {
      final c = await CreatureService().getCreature();
      _safeSetState(() {
        _creatureLevel = (c['level'] as num?)?.toInt() ?? 1;
        _creatureStage = (c['stage'] as num?)?.toInt() ?? 0;
      });
    });
  }

  /// study 데이터 파싱 → UI 상태에 반영 (로컬/Firebase 공용)
  void _parseStudyData(Map<String, dynamic> data, String d) {
    // timeRecords
    try {
      final trRaw = data['timeRecords'] as Map<String, dynamic>?;
      if (trRaw != null && trRaw[d] != null) {
        final rec = TimeRecord.fromMap(d, trRaw[d] as Map<String, dynamic>);
        _wake = rec.wake; _studyStart = rec.study; _studyEnd = rec.studyEnd;
        _outing = rec.outing; _returnHome = rec.returnHome; _bedTime = rec.bedTime;
        _mealStart = rec.mealStart; _mealEnd = rec.mealEnd;
        _todayMeals = rec.meals; _noOuting = rec.noOuting;
        _outingMinutes = rec.outingMinutes;
      }
    } catch (e) { debugPrint('[Home] timeRecords: $e'); }

    // studyTimeRecords
    try {
      final strRaw = data['studyTimeRecords'] as Map<String, dynamic>?;
      if (strRaw != null && strRaw[d] != null) {
        _effMin = StudyTimeRecord.fromMap(d, strRaw[d] as Map<String, dynamic>).effectiveMinutes;
      }
    } catch (e) { debugPrint('[Home] studyTimeRecords: $e'); }

    _grade = DailyGrade.calculate(
      date: d, wakeTime: _wake,
      studyStartTime: _studyStart, effectiveMinutes: _effMin);

    // orderData
    try {
      final od = data['orderData'];
      if (od is Map && od.isNotEmpty) {
        _orderData = OrderData.fromMap(Map<String, dynamic>.from(od));
      }
    } catch (e) { debugPrint('[Home] order: $e'); }

    // todos
    try {
      final todosRaw = data['todos'];
      if (todosRaw is Map) {
        final todosMap = Map<String, dynamic>.from(todosRaw);
        if (todosMap[d] != null) {
          _todayTodos = TodoDaily.fromMap(Map<String, dynamic>.from(todosMap[d] as Map));
        }
        final cutoff = DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(const Duration(days: 7)));
        final history = <String, double>{};
        for (final entry in todosMap.entries) {
          if (entry.key.compareTo(cutoff) >= 0) {
            try {
              final td = TodoDaily.fromMap(Map<String, dynamic>.from(entry.value as Map));
              history[entry.key] = td.completionRate;
            } catch (_) {}
          }
        }
        _weeklyHistoryCache = history;
      }
    } catch (e) { debugPrint('[Home] todos: $e'); }
  }

  /// today 문서 파싱 → UI 상태에 반영 (Phase C: 1~2KB 경량 문서)
  void _parseTodayData(Map<String, dynamic> data, String d) {
    // timeRecords (today 문서에서는 date 키 없이 바로 들어있음)
    try {
      final tr = data['timeRecords'];
      if (tr is Map && tr.isNotEmpty) {
        // today 문서는 flat 구조: timeRecords.wake, timeRecords.outing 등
        // 또는 기존 구조: timeRecords.{date}.{fields}
        if (tr.containsKey('wake') || tr.containsKey('study') || tr.containsKey('outing') || tr.containsKey('studyStart')) {
          // flat 구조 (Phase C)
          _wake = tr['wake'] as String?;
          _studyStart = tr['study'] as String? ?? tr['studyStart'] as String?;
          _studyEnd = tr['studyEnd'] as String?;
          _outing = tr['outing'] as String?;
          _returnHome = tr['returnHome'] as String?;
          _bedTime = tr['bedTime'] as String?;
          _mealStart = tr['mealStart'] as String?;
          _mealEnd = tr['mealEnd'] as String?;
          _noOuting = tr['noOuting'] == true;
          _outingMinutes = (tr['outingMinutes'] as num?)?.toInt();
          if (tr['meals'] is List) {
            _todayMeals = (tr['meals'] as List)
                .map((m) => MealEntry.fromMap(Map<String, dynamic>.from(m as Map)))
                .toList();
          }
        } else if (tr.containsKey(d)) {
          // 기존 구조 (study doc 호환)
          final rec = TimeRecord.fromMap(d, Map<String, dynamic>.from(tr[d] as Map));
          _wake = rec.wake; _studyStart = rec.study; _studyEnd = rec.studyEnd;
          _outing = rec.outing; _returnHome = rec.returnHome; _bedTime = rec.bedTime;
          _mealStart = rec.mealStart; _mealEnd = rec.mealEnd;
          _todayMeals = rec.meals; _noOuting = rec.noOuting;
          _outingMinutes = rec.outingMinutes;
        }
      }
    } catch (e) { debugPrint('[Home] today timeRecords: $e'); }

    // studyTime
    try {
      final st = data['studyTime'];
      if (st is Map) {
        _effMin = (st['total'] as num?)?.toInt() ?? 0;
      }
    } catch (e) { debugPrint('[Home] today studyTime: $e'); }

    // fallback: studyTimeRecords (마이그레이션 직후 호환)
    if (_effMin == 0) {
      try {
        final strRaw = data['studyTimeRecords'];
        if (strRaw is Map && strRaw[d] != null) {
          _effMin = StudyTimeRecord.fromMap(d, Map<String, dynamic>.from(strRaw[d] as Map)).effectiveMinutes;
        }
      } catch (_) {}
    }

    _grade = DailyGrade.calculate(
      date: d, wakeTime: _wake,
      studyStartTime: _studyStart, effectiveMinutes: _effMin);

    // orderData
    try {
      final od = data['orderData'];
      if (od is Map && od.isNotEmpty) {
        _orderData = OrderData.fromMap(Map<String, dynamic>.from(od));
      }
    } catch (e) { debugPrint('[Home] today order: $e'); }

    // todos (Phase C: List format)
    try {
      final todosRaw = data['todos'];
      if (todosRaw is List) {
        // Phase C: flat list of todo items
        final items = todosRaw.map((t) {
          if (t is Map) {
            return TodoItem(
              id: t['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
              title: t['title']?.toString() ?? '',
              completed: t['done'] == true || t['completed'] == true,
              completedAt: t['completedAt'] as String?,
            );
          }
          return null;
        }).whereType<TodoItem>().toList();
        _todayTodos = TodoDaily(date: d, items: items);
      } else if (todosRaw is Map) {
        // study doc fallback
        final todosMap = Map<String, dynamic>.from(todosRaw);
        if (todosMap[d] != null) {
          _todayTodos = TodoDaily.fromMap(Map<String, dynamic>.from(todosMap[d] as Map));
        }
      }
    } catch (e) { debugPrint('[Home] today todos: $e'); }
  }

  /// 독립 실행 헬퍼 — 실패해도 앱에 영향 없음
  void _tryRefresh(String name, Future<void> Function() fn) {
    Future(() async {
      try {
        await fn().timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[Home] refresh $name: FAIL — $e');
      }
    });
  }

  Future<void> _checkPendingWake() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (_alarm.nfcWakeEnabled) return;
    final pending = await AlarmService.hasPendingQrWake();
    if (pending && mounted) {
      final result = await Navigator.push(context,
          MaterialPageRoute(builder: (_) => QrWakeScreen(settings: _alarm)));
      if (result == true) {
        await AlarmService.completeQrWake();
        final time = DateFormat('HH:mm').format(DateTime.now());
        await _sleepSvc.completeWakeRecord(time);
        _load();
      }
    }
  }

  /// 학습일 계산: 새벽 0~4시는 전날로 취급
  String _studyDate() => StudyDateUtils.todayKey();

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  /// ★ 스트림 + _load(즉시) + 백그라운드 아카이브
  Future<void> _runStartup() async {
    final fb = FirebaseService();
    // 스트림과 로드를 즉시 시작
    _startFirebaseListener();
    _load();
    // ★ 자동 아카이브 (7일 이전 데이터 → 월별 아카이브, UI 블로킹 없음)
    fb.autoArchive().catchError((e) {
      debugPrint('[Home] autoArchive error: $e');
    });
    // 역마이그레이션은 백그라운드에서 실행 (UI 블로킹 없음)
    fb.runReverseMigration().then((_) {
      if (mounted) {
        debugPrint('[Home] reverse migration 완료 → 리로드');
        _load();
      }
    }).catchError((e) {
      debugPrint('[Home] reverse migration error: $e');
    });
  }

  /// 1회성 마이그레이션: 2026-02-23 기록 → 2026-02-22로 이관, 귀가 23:30 설정
  Future<void> _runMigration0223() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('migration_0223_done') == true) return;
    try {
      await FirebaseService().migrateDateRecords(
        fromDate: '2026-02-23',
        toDate: '2026-02-22',
        timeRecordOverrides: {'returnHome': '23:30'},
      );
      await prefs.setBool('migration_0223_done', true);
      if (mounted) _load();
    } catch (e) {
      debugPrint('Migration 0223 error: $e');
    }
  }

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.gold;

  Widget _staggered(int index, Widget child) {
    final i = index.clamp(0, _cardCount - 1);
    return FadeTransition(
      opacity: _fadeAnims[i],
      child: SlideTransition(position: _slideAnims[i], child: child));
  }

  // ══════════════════════════════════════════
  //  빌드: BottomNav (대시보드 / 도구)
  // ══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        _paperBackground(),
        IndexedStack(
          index: _tab,
          children: [
            SafeArea(child: _dashboardPage()),
            SafeArea(child: _todoPage()),
            SafeArea(child: _focusPage()),
            SafeArea(child: _recordsPage()),
            const SafeArea(child: ProgressScreen()),
            SafeArea(child: CalendarScreen(embedded: true)),
          ],
        ),
      ]),
      bottomNavigationBar: _bottomNav(),
      floatingActionButton: _tab == 0 ? CreatureFloatButton(
        level: _creatureLevel,
        stage: _creatureStage,
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const HabitatScreen()))
          .then((_) => _load()),
      ) : null,
    );
  }

  Widget _paperBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: const [0.0, 0.3, 0.7, 1.0],
            colors: _dk
              ? [const Color(0xFF1C1410), const Color(0xFF1A1210),
                 const Color(0xFF1D1512), const Color(0xFF181010)]
              : [const Color(0xFFFDF9F2), const Color(0xFFFAF5EC),
                 const Color(0xFFF6F0E5), const Color(0xFFF2ECDF)],
          ),
        ),
        child: CustomPaint(painter: PaperGrainPainter(_dk)),
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.cardDark : Colors.white,
        border: Border(top: BorderSide(color: _border.withOpacity(0.3), width: 0.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(_dk ? 0.3 : 0.04),
          blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _navItem(0, Icons.dashboard_rounded, '홈'),
            _navItem(1, Icons.checklist_rounded, 'Todo'),
            _navItem(2, Icons.local_fire_department_rounded, '포커스'),
            _navItem(3, Icons.bar_chart_rounded, '기록'),
            _navItem(4, Icons.trending_up_rounded, '진행도'),
            _navItem(5, Icons.calendar_month_rounded, '캘린더'),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final sel = _tab == index;
    final c = sel
      ? (_dk ? BotanicalColors.lanternGold : BotanicalColors.primary)
      : _textMuted;
    final showLive = index == 2 && _ft.isRunning && !sel;
    return GestureDetector(
      onTap: () => _safeSetState(() => _tab = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, size: 22, color: c),
            if (showLive) Positioned(right: -3, top: -2,
              child: Container(width: 7, height: 7,
                decoration: BoxDecoration(
                  color: BotanicalColors.primary, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: BotanicalColors.primary.withOpacity(0.5),
                    blurRadius: 4, spreadRadius: 1)]))),
          ]),
          const SizedBox(height: 3),
          Text(label, style: BotanicalTypo.label(
            size: 10, weight: sel ? FontWeight.w800 : FontWeight.w600, color: c)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 0: 대시보드
  // ══════════════════════════════════════════

  Widget _dashboardPage() {
    return RefreshIndicator(
      color: BotanicalColors.primary,
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // 헤더 (날짜 + 아이콘)
          _staggered(0, _weatherHeaderBar()),
          const SizedBox(height: 12),
          _staggered(0, _orderPortalChip()),
          const SizedBox(height: 12),
          _staggered(1, _nfcStatusCard()),
          const SizedBox(height: 14),
          // ★ Stage4: 날씨+성적 2컬럼 + 순공시간 (NFC카드 아래)
          _staggered(2, _weatherGradeRow()),
          const SizedBox(height: 10),
          _staggered(2, _studyTimeCard()),
          const SizedBox(height: 16),
          if (_todayTimeline.isNotEmpty || _wake != null) ...[
            _staggered(3, _locationSummaryCard()),
            const SizedBox(height: 16),
          ],
          if (_ft.isRunning) ...[
            _staggered(4, _activeFocusBanner()),
            const SizedBox(height: 12),
          ],
          // ★ #9: 데일리 메모 컴팩트 위젯
          if (_dailyMemos.isNotEmpty || true) ...[
            _staggered(4, _dashboardMemoWidget()),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          // ★ 기존 _orderPortalCard() 제거됨
          _staggered(4, _quickToolsRow()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 2: 도구 (자동화 + 시스템)
  // ══════════════════════════════════════════

  Widget _toolsPage() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Text('도구', style: BotanicalTypo.heading(
          size: 26, weight: FontWeight.w800, color: _textMain)),
        const SizedBox(height: 4),
        Text('자동화와 시스템 관리', style: BotanicalTypo.label(
          size: 13, color: _textMuted)),
        const SizedBox(height: 24),

        _sectionHeader('⚡', '자동화'),
        const SizedBox(height: 10),
        _toolCard(
          icon: '📡', label: 'NFC 관리',
          subtitle: _nfc.tags.isNotEmpty ? '${_nfc.tags.length}개 태그 등록됨' : '태그 등록 및 설정',
          color: const Color(0xFFB05C8A),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => NfcScreen()))
            .then((_) => _load()),
        ),
        _toolCard(
          icon: '⏰', label: '기상 알람',
          subtitle: _alarm.enabled ? '목표 ${_alarm.targetWakeTime}' : '알람 설정',
          color: const Color(0xFFD4953B),
          trailing: _wake != null ? Text('✓', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: _accent)) : null,
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AlarmSettingsScreen()))
            .then((_) => _load()),
        ),
        _toolCard(
          icon: '📍', label: '위치 추적',
          subtitle: _locationTracking
            ? (_currentPlace ?? 'GPS 추적 중')
            : 'GPS 동선 기록',
          color: const Color(0xFF3B8A6B),
          isLive: _locationTracking,
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const LocationScreen()))
            .then((_) => _load()),
        ),
        const SizedBox(height: 20),

        _sectionHeader('⚙️', '시스템'),
        const SizedBox(height: 10),
        // ★ #5: 데일리 인사이트
        _toolCard(
          icon: '💡', label: '데일리 인사이트',
          subtitle: '학습 회고 & 인사이트 기록',
          color: const Color(0xFFF59E0B),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InsightScreen())),
        ),
        const SizedBox(height: 20),

        _sectionHeader('🔧', '앱 설정'),
        const SizedBox(height: 10),
        _toolCard(
          icon: '⚙️', label: '설정',
          subtitle: '앱 설정 및 데이터 관리',
          color: _textSub,
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ══════════════════════════════════════════
  //  TAB 2: 기록
  // ══════════════════════════════════════════

  Widget _recordsPage() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Text('기록', style: BotanicalTypo.heading(
          size: 26, weight: FontWeight.w800, color: _textMain)),
        const SizedBox(height: 4),
        Text('학습 통계와 생활 기록', style: BotanicalTypo.label(
          size: 13, color: _textMuted)),
        const SizedBox(height: 16),

        // ── 통계 화면 (세그먼트 컨트롤 포함) ──
        const StatisticsScreen(embedded: true),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _sectionHeader(String emoji, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(title, style: BotanicalTypo.label(
          size: 13, weight: FontWeight.w800, letterSpacing: 0.5, color: _textMain)),
      ]),
    );
  }

  Widget _toolCard({
    required String icon, required String label, required String subtitle,
    required Color color, required VoidCallback onTap,
    bool isLive = false, Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _dk ? color.withOpacity(0.06) : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _dk
            ? color.withOpacity(0.12) : color.withOpacity(0.08)),
          boxShadow: _dk ? null : [
            BoxShadow(color: color.withOpacity(0.04),
              blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(_dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Stack(clipBehavior: Clip.none, children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                if (isLive)
                  Positioned(right: -3, top: -3,
                    child: Container(width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: BotanicalColors.success, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: BotanicalColors.success.withOpacity(0.5),
                          blurRadius: 6, spreadRadius: 1)]))),
              ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text(subtitle, style: BotanicalTypo.label(
              size: 11, color: _textMuted),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          ])),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: _textMuted.withOpacity(0.5)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  ① 헤더 + 날씨 통합 상단바
  // ══════════════════════════════════════════

  Widget _weatherHeaderBar() {
    final now = DateTime.now();
    final wd = ['월','화','수','목','금','토','일'][now.weekday - 1];
    final w = _weatherData;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CHEONHONG', style: BotanicalTypo.brand(
            color: _dk ? BotanicalColors.lanternGold : BotanicalColors.primary)),
          const SizedBox(height: 4),
          Row(children: [
            Text('${now.month}월 ${now.day}일 ($wd)',
              style: BotanicalTypo.heading(size: 22, weight: FontWeight.w800, color: _textMain)),
            if (w != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  await WeatherService().sendWeatherReport();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('📩 날씨 정보를 Telegram으로 전송했습니다'),
                      duration: Duration(seconds: 2)));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(w.emoji, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 3),
                    Text('${w.temp.round()}°', style: BotanicalTypo.number(
                      size: 12, weight: FontWeight.w700, color: _textSub)),
                    if (_weather.needsUmbrella(w)) ...[
                      const SizedBox(width: 2),
                      const Text('☂️', style: TextStyle(fontSize: 10)),
                    ],
                  ]),
                ),
              ),
            ],
          ]),
        ])),
        Row(children: [
          GestureDetector(
            onTap: _showAddMemoDialog,
            child: Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.edit_note_rounded, size: 20, color: _textMuted)),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.settings_outlined, size: 18, color: _textMuted)),
          ),
        ]),
      ],
    );
  }

  // ══════════════════════════════════════════
  //  ★ #9: 데일리 메모 대시보드 위젯
  // ══════════════════════════════════════════

  Widget _dashboardMemoWidget() {
    return GestureDetector(
      onTap: _showAddMemoDialog,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dk ? const Color(0xFF2A2218).withOpacity(0.6) : const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB07D3A).withOpacity(_dk ? 0.15 : 0.1)),
          boxShadow: _dk ? null : [
            BoxShadow(color: const Color(0xFFB07D3A).withOpacity(0.04),
              blurRadius: 12, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFB07D3A).withOpacity(_dk ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(8)),
              child: const Text('📝', style: TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Text('오늘의 메모', style: BotanicalTypo.label(
              size: 12, weight: FontWeight.w700,
              color: _dk ? const Color(0xFFD4A66A) : const Color(0xFFB07D3A))),
            const Spacer(),
            if (_dailyMemos.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFB07D3A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('${_dailyMemos.length}', style: BotanicalTypo.label(
                  size: 10, weight: FontWeight.w800,
                  color: const Color(0xFFB07D3A)))),
            const SizedBox(width: 6),
            Icon(Icons.add_circle_outline_rounded, size: 16,
              color: _textMuted.withOpacity(0.5)),
          ]),
          if (_dailyMemos.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._dailyMemos.take(3).map((memo) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: _textMuted.withOpacity(0.3),
                      shape: BoxShape.circle))),
                const SizedBox(width: 8),
                Expanded(child: Text(memo, style: BotanicalTypo.label(
                  size: 11, color: _textSub),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            )),
            if (_dailyMemos.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${_dailyMemos.length - 3}개 더보기',
                  style: BotanicalTypo.label(size: 10, weight: FontWeight.w600,
                    color: _textMuted.withOpacity(0.5)))),
          ] else ...[
            const SizedBox(height: 8),
            Text('탭하여 메모를 추가하세요', style: BotanicalTypo.label(
              size: 11, color: _textMuted.withOpacity(0.5))),
          ],
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  ★ Stage4: 날씨 + 성적 2컬럼 컴팩트 카드
  // ══════════════════════════════════════════

  Widget _weatherGradeRow() {
    final w = _weatherData;
    final g = _grade ?? DailyGrade.calculate(date: _studyDate());
    final gc = BotanicalColors.gradeColor(g.grade);
    final flower = GrowthMetaphor.gradeFlower(g.grade);

    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── 날씨 디테일 카드 (LEFT) — 체감온도 + 옷차림 팁 ──
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dk ? const Color(0xFF1A2535) : const Color(0xFFF0F4FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _dk
            ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('체감온도', style: BotanicalTypo.label(
            size: 10, weight: FontWeight.w600, letterSpacing: 1, color: _textMuted)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text(w != null ? '${w.feelsLike.round()}°' : '--°',
              style: BotanicalTypo.number(size: 28, weight: FontWeight.w700,
                color: _dk ? Colors.white : _textMain)),
            const SizedBox(width: 6),
            if (w != null)
              Text('습도 ${w.humidity}%', style: BotanicalTypo.label(
                size: 10, color: _textMuted)),
          ]),
          const SizedBox(height: 6),
          Text(w != null ? _weather.getClothingAdvice(w) : '날씨 로딩 중',
            style: BotanicalTypo.label(size: 10, color: _textSub),
            maxLines: 2),
        ]),
      )),
      const SizedBox(width: 10),
      // ── 성적 카드 (RIGHT) ──
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: _dk
              ? [gc.withOpacity(0.15), gc.withOpacity(0.08)]
              : [gc.withOpacity(0.07), gc.withOpacity(0.03)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: gc.withOpacity(_dk ? 0.3 : 0.15)),
          boxShadow: [BoxShadow(
            color: gc.withOpacity(_dk ? 0.12 : 0.06),
            blurRadius: 16, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(flower, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text('TODAY', style: BotanicalTypo.label(
              size: 10, weight: FontWeight.w700, letterSpacing: 1, color: gc)),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text(g.grade, style: BotanicalTypo.heading(size: 22, weight: FontWeight.w900, color: gc)),
            const SizedBox(width: 6),
            Text(g.totalScore.toStringAsFixed(1), style: BotanicalTypo.number(
              size: 13, weight: FontWeight.w300,
              color: _dk ? Colors.white54 : _textMuted)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (g.totalScore / 100).clamp(0.0, 1.0),
              backgroundColor: _dk ? Colors.white.withOpacity(0.08) : gc.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(gc),
              minHeight: 3)),
        ]),
      )),
    ]));
  }

  // ── 순공시간 카드 (full width) ──

  Widget _studyTimeCard() {
    final h = _effMin ~/ 60;
    final m = _effMin % 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1E3A2F), const Color(0xFF1A2E26)]
            : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BotanicalColors.primary.withOpacity(_dk ? 0.3 : 0.15)),
        boxShadow: [BoxShadow(
          color: BotanicalColors.primary.withOpacity(_dk ? 0.12 : 0.06),
          blurRadius: 16, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: BotanicalColors.primary.withOpacity(_dk ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.timer_outlined, size: 18,
            color: _dk ? BotanicalColors.primaryLight : BotanicalColors.primary)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('순공시간', style: BotanicalTypo.label(
            size: 11, weight: FontWeight.w700,
            color: _dk ? BotanicalColors.primaryLight : BotanicalColors.primary)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text('$h', style: BotanicalTypo.number(size: 32, weight: FontWeight.w300,
              color: _dk ? Colors.white : BotanicalColors.textMain)),
            Text('h ', style: BotanicalTypo.label(size: 13, weight: FontWeight.w300,
              color: _dk ? Colors.white54 : BotanicalColors.textSub)),
            Text('${m.toString().padLeft(2, '0')}', style: BotanicalTypo.number(
              size: 22, weight: FontWeight.w300,
              color: _dk ? Colors.white70 : BotanicalColors.textSub)),
            Text('m', style: BotanicalTypo.label(size: 11, weight: FontWeight.w300,
              color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(width: 70,
            child: ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (_effMin / 480).clamp(0.0, 1.0),
                backgroundColor: _dk
                  ? Colors.white.withOpacity(0.08)
                  : BotanicalColors.primary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(
                  _dk ? BotanicalColors.primaryLight : BotanicalColors.primary),
                minHeight: 4))),
          const SizedBox(height: 3),
          Text('목표 8h · ${(_effMin / 480 * 100).toInt()}%',
            style: BotanicalTypo.label(size: 10,
              color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ② 히어로 카드 (레거시 — 직접 호출 안 함)
  // ══════════════════════════════════════════

  Widget _heroStatsRow() {
    final g = _grade ?? DailyGrade.calculate(
      date: _studyDate());
    final gc = BotanicalColors.gradeColor(g.grade);
    final flower = GrowthMetaphor.gradeFlower(g.grade);
    final h = _effMin ~/ 60;
    final m = _effMin % 60;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: _dk
                ? [const Color(0xFF1E3A2F), const Color(0xFF1A2E26)]
                : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BotanicalColors.primary.withOpacity(_dk ? 0.3 : 0.15)),
            boxShadow: [BoxShadow(
              color: BotanicalColors.primary.withOpacity(_dk ? 0.15 : 0.08),
              blurRadius: 20, offset: const Offset(0, 6))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: BotanicalColors.primary.withOpacity(_dk ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.timer_outlined, size: 14,
                  color: _dk ? BotanicalColors.primaryLight : BotanicalColors.primary)),
              const SizedBox(width: 8),
              Text('순공시간', style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w700,
                color: _dk ? BotanicalColors.primaryLight : BotanicalColors.primary)),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
              Text('$h', style: BotanicalTypo.number(size: 38, weight: FontWeight.w300,
                color: _dk ? Colors.white : BotanicalColors.textMain)),
              Text('h ', style: BotanicalTypo.label(size: 15, weight: FontWeight.w300,
                color: _dk ? Colors.white54 : BotanicalColors.textSub)),
              Text('${m.toString().padLeft(2, '0')}', style: BotanicalTypo.number(
                size: 26, weight: FontWeight.w300,
                color: _dk ? Colors.white70 : BotanicalColors.textSub)),
              Text('m', style: BotanicalTypo.label(size: 13, weight: FontWeight.w300,
                color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_effMin / 480).clamp(0.0, 1.0),
                backgroundColor: _dk
                  ? Colors.white.withOpacity(0.08)
                  : BotanicalColors.primary.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(
                  _dk ? BotanicalColors.primaryLight : BotanicalColors.primary),
                minHeight: 4)),
            const SizedBox(height: 3),
            Text('목표 8h · ${(_effMin / 480 * 100).toInt()}%',
              style: BotanicalTypo.label(size: 10,
                color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
          ]),
        )),
        const SizedBox(width: 10),
        Expanded(child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: _dk
                ? [gc.withOpacity(0.15), gc.withOpacity(0.08)]
                : [gc.withOpacity(0.06), gc.withOpacity(0.03)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: gc.withOpacity(_dk ? 0.3 : 0.15)),
            boxShadow: [BoxShadow(
              color: gc.withOpacity(_dk ? 0.12 : 0.08),
              blurRadius: 20, offset: const Offset(0, 6))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: gc.withOpacity(_dk ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text(flower, style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 8),
              Text('TODAY', style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w700, letterSpacing: 1.5, color: gc)),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
              Text(g.grade, style: BotanicalTypo.heading(size: 34, weight: FontWeight.w900,
                color: gc)),
              const SizedBox(width: 8),
              Text(g.totalScore.toStringAsFixed(1),
                style: BotanicalTypo.number(size: 22, weight: FontWeight.w300,
                  color: _dk ? Colors.white54 : BotanicalColors.textMuted)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (g.totalScore / 100).clamp(0.0, 1.0),
                backgroundColor: _dk ? Colors.white.withOpacity(0.08) : gc.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(gc),
                minHeight: 4)),
            const SizedBox(height: 3),
            Text('${g.totalScore.toStringAsFixed(0)} / 100',
              style: BotanicalTypo.label(size: 10,
                color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
          ]),
        )),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ③ 스코어 브레이크다운
  // ══════════════════════════════════════════

  Widget _scoreBreakdown() {
    final g = _grade ?? DailyGrade.calculate(
      date: _studyDate());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        _scoreCell('기상', _fmt12h(_wake), g.wakeScore, 25,
          BotanicalColors.gold, Icons.wb_sunny_outlined),
        _scoreDivider(),
        _scoreCell('공부시작', _fmt12h(_studyStart), g.studyStartScore, 25,
          BotanicalColors.subjectData, Icons.menu_book_outlined),
        _scoreDivider(),
        _scoreCell('순공', '${_effMin ~/ 60}h${_effMin % 60}m', g.studyTimeScore, 50,
          BotanicalColors.primary, Icons.schedule_outlined),
      ]),
    );
  }

  Widget _scoreCell(String label, String value, double score, double max,
      Color color, IconData icon) {
    final pct = (score / max).clamp(0.0, 1.0);
    return Expanded(child: Column(children: [
      Icon(icon, size: 16, color: color.withOpacity(0.7)),
      const SizedBox(height: 6),
      Text(value, style: BotanicalTypo.label(
        size: 13, weight: FontWeight.w700, color: _textMain)),
      const SizedBox(height: 2),
      Text(label, style: BotanicalTypo.label(size: 10, color: _textMuted)),
      const SizedBox(height: 8),
      SizedBox(width: 34, height: 34,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: pct, strokeWidth: 2.5,
            backgroundColor: _dk ? Colors.white.withOpacity(0.06) : color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(color)),
          Text(score.toStringAsFixed(0), style: BotanicalTypo.label(
            size: 10, weight: FontWeight.w800, color: color)),
        ])),
    ]));
  }

  Widget _scoreDivider() => Container(
    width: 1, height: 65, color: _border.withOpacity(0.4));

  // ══════════════════════════════════════════
  //  포커스 활성 배너
  // ══════════════════════════════════════════

  Widget _activeFocusBanner() {
    final st = _ft.getCurrentState();
    final mc = BotanicalColors.subjectColor(st.subject);
    return GestureDetector(
      onTap: () => _safeSetState(() => _tab = 2), // 포커스 탭으로 이동
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [mc.withOpacity(_dk ? 0.15 : 0.06), mc.withOpacity(_dk ? 0.05 : 0.02)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: mc.withOpacity(0.2))),
        child: Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(color: mc, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: mc.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)])),
          const SizedBox(width: 12),
          Text('${st.mode == 'study' ? '📖' : st.mode == 'lecture' ? '🎧' : '☕'} ${st.subject}',
            style: BotanicalTypo.label(size: 13, weight: FontWeight.w600, color: _textMain)),
          const Spacer(),
          Text(st.mainTimerFormatted, style: BotanicalTypo.number(
            size: 20, weight: FontWeight.w600, color: mc)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: mc.withOpacity(_dk ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8)),
            child: Text('순공 ${st.effectiveTimeFormatted}',
              style: BotanicalTypo.label(size: 10, weight: FontWeight.w700, color: mc))),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: _textMuted),
        ]),
      ),
    );
  }

}