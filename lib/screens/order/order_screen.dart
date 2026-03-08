import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/order_models.dart';
import '../../services/firebase_service.dart';
import 'order_theme.dart';
import 'order_today_tab.dart';
import 'order_goals_tab.dart';
import 'order_habits_tab.dart';
import 'order_stats_tab.dart';
import 'order_expense_tab.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — COMPASS PORTAL v4.0
/// 메인 스캐폴드 · 네비게이션 · 상태 관리
/// + NFC 실시간 연동 · Overwatch 자동감지 · 습관 큐 시스템
/// ═══════════════════════════════════════════════════════════

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});
  @override State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen>
    with TickerProviderStateMixin {
  final _fb = FirebaseService();
  OrderData _data = OrderData();
  bool _loading = true;
  int _tab = 0;

  /// NFC 이벤트 기반 실제 시간 (role → HH:mm)
  Map<String, String> _nfcActualTimes = {};

  late AnimationController _blobCtrl;
  late AnimationController _pulseCtrl;

  static const String _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';

  @override
  void initState() {
    super.initState();
    _blobCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 8))..repeat();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

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

  // ═══ DATA ═══
  Future<void> _load() async {
    // 1) 캐시에서 즉시 로드 → UI 먼저 표시
    try {
      final raw = await _fb.getStudyData();
      if (raw != null) {
        final od = raw['orderData'];
        if (od is Map && od.isNotEmpty) {
          _data = OrderData.fromMap(Map<String, dynamic>.from(od));
        }

        // timeRecords[today] → _nfcActualTimes 기본값 (NFC가 없을 때 fallback)
        final today = todayStr();
        final tr = raw['timeRecords'];
        if (tr is Map && tr[today] is Map) {
          final dayRec = Map<String, dynamic>.from(tr[today] as Map);
          final Map<String, String> baseTimes = {};
          for (final role in ['wake', 'outing', 'returnHome', 'study', 'sleep']) {
            final val = dayRec[role];
            if (val is String && val.isNotEmpty) {
              baseTimes[role] = val;
            }
          }
          if (baseTimes.isNotEmpty) {
            _nfcActualTimes = baseTimes;
            debugPrint('[Compass] timeRecords 기본값 적용: $baseTimes');
          }
        }
      }
    } catch (_) {}

    _safeSetState(() => _loading = false);

    // 2) NFC 이벤트는 백그라운드 (NFC 있으면 override)
    _loadNfcEventsBackground();
  }

  void _loadNfcEventsBackground() async {
    try {
      await _loadNfcEvents().timeout(const Duration(seconds: 5));
      _safeSetState(() {});
    } catch (_) {
      debugPrint('[Compass] NFC 이벤트 로딩 타임아웃');
    }
  }

  /// NFC 이벤트에서 실제 시간 추출
  /// Firestore: users/{uid}/nfcEvents/{date} → { events: [...] }
  /// 각 이벤트: { role: "wake", timestamp: "...", ... }
  Future<void> _loadNfcEvents() async {
    try {
      final today = todayStr();
      final doc = await FirebaseFirestore.instance
          .doc('users/$_uid/nfcEvents/$today')
          .get()
          .timeout(const Duration(seconds: 5));

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      final Map<String, String> times = {};

      // 구조 1: events 배열
      if (data['events'] is List) {
        final events = List<Map<String, dynamic>>.from(
          (data['events'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        for (final evt in events) {
          final role = evt['role'] as String?;
          final ts = evt['timestamp'] as String?;
          final action = evt['action'] as String?;
          if (role != null && ts != null) {
            try {
              final dt = DateTime.parse(ts);
              final hhmm = '${dt.hour.toString().padLeft(2, '0')}:'
                  '${dt.minute.toString().padLeft(2, '0')}';
              // outing role: start만 외출 시간으로 사용 (end는 귀가)
              if (role == 'outing') {
                if (action == 'start') {
                  times[role] = hhmm;
                }
                // end(귀가)는 별도 키로 저장
                if (action == 'end') {
                  times['returnHome'] = hhmm;
                }
              } else {
                // 동일 role 여러 번이면 최신 것 사용
                times[role] = hhmm;
              }
            } catch (_) {}
          }
        }
      }

      // 구조 2: 개별 role 필드 (wake, ready, outing, study, sleep)
      for (final role in ['wake', 'outing', 'study', 'sleep']) {
        if (data[role] != null && times[role] == null) {
          final val = data[role];
          if (val is String) {
            // ISO string or HH:mm
            if (val.contains('T')) {
              try {
                final dt = DateTime.parse(val);
                times[role] = '${dt.hour.toString().padLeft(2, '0')}:'
                    '${dt.minute.toString().padLeft(2, '0')}';
              } catch (_) {
                times[role] = val;
              }
            } else {
              times[role] = val;
            }
          } else if (val is Timestamp) {
            final dt = val.toDate();
            times[role] = '${dt.hour.toString().padLeft(2, '0')}:'
                '${dt.minute.toString().padLeft(2, '0')}';
          } else if (val is Map) {
            // { timestamp: "...", ... } 형태
            final ts = val['timestamp'] ?? val['time'];
            if (ts is String) {
              try {
                final dt = DateTime.parse(ts);
                times[role] = '${dt.hour.toString().padLeft(2, '0')}:'
                    '${dt.minute.toString().padLeft(2, '0')}';
              } catch (_) {}
            } else if (ts is Timestamp) {
              final dt = ts.toDate();
              times[role] = '${dt.hour.toString().padLeft(2, '0')}:'
                  '${dt.minute.toString().padLeft(2, '0')}';
            }
          }
        }
      }

      _nfcActualTimes = times;
      debugPrint('[Compass] NFC 실제 시간: $_nfcActualTimes');
    } catch (e) {
      debugPrint('[Compass] NFC 이벤트 로딩 실패: $e');
    }
  }

  Future<void> _save() async {
    try { await _fb.updateField('orderData', _data.toMap()); } catch (_) {}
  }

  void _update(VoidCallback fn) {
    _safeSetState(fn);
    _save();
  }

  // _seed() 제거됨 — 시드 데이터를 Firestore에 쓰지 않음

  // ═══ BUILD ═══
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: OC.bg,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: OC.accent))
            : Stack(children: [
                Positioned(top: -60, right: -40,
                  child: _meshSpot(OC.accent, 200, .06)),
                Positioned(bottom: 100, left: -60,
                  child: _meshSpot(OC.amber, 180, .05)),
                Positioned(top: 300, right: -80,
                  child: _meshSpot(OC.success, 160, .04)),
                SafeArea(child: Column(children: [
                  _nav(),
                  Expanded(child: IndexedStack(index: _tab, children: [
                    OrderTodayTab(
                      data: _data, onUpdate: _update,
                      onLoad: _load,
                      nfcActualTimes: _nfcActualTimes),
                    OrderGoalsTab(
                      data: _data, onUpdate: _update),
                    OrderHabitsTab(
                      data: _data, onUpdate: _update,
                      blobCtrl: _blobCtrl),
                    OrderExpenseTab(
                      data: _data, onUpdate: _update),
                    OrderStatsTab(data: _data),
                  ])),
                ])),
              ]),
      ),
    );
  }

  Widget _meshSpot(Color c, double size, double op) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [c.withOpacity(op), c.withOpacity(0)])),
  );

  // ═══ NAVIGATION ═══
  Widget _nav() {
    final tabs = [
      ('오늘', Icons.wb_sunny_rounded),
      ('목표', Icons.flag_rounded),
      ('습관', Icons.local_fire_department_rounded),
      ('회계', Icons.receipt_long_rounded),
      ('통계', Icons.bar_chart_rounded),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OC.card, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OC.border.withOpacity(.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(children: List.generate(tabs.length, (i) {
        final sel = _tab == i;
        return Expanded(child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _safeSetState(() => _tab = i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? OC.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: sel
                  ? [BoxShadow(color: OC.accent.withOpacity(.25),
                      blurRadius: 8, offset: const Offset(0, 2))]
                  : null),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(tabs[i].$2, size: 20,
                color: sel ? Colors.white : OC.text3),
              const SizedBox(height: 2),
              Text(tabs[i].$1, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: sel ? Colors.white : OC.text3)),
            ]),
          ),
        ));
      })),
    );
  }
}