import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with SingleTickerProviderStateMixin {
  final _loc = LocationService();
  late TabController _tab;

  List<LocationRecord> _records = [];
  List<KnownPlace> _places = [];
  List<BehaviorTimelineEntry> _timeline = [];
  Map<String, int> _placeSummary = {};
  bool _loading = true;
  bool _tracking = false;
  DateTime _selectedDate = DateTime.now(); // N3: 타임라인 날짜 선택

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

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

  Future<void> _load() async {
    // ★ 즉시 캐시로 표시 (0ms)
    _tracking = _loc.isTracking;
    _safeSetState(() => _loading = false); // 로딩 스피너 즉시 제거

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    // ★ 병렬로 모든 데이터 로드 (각각 독립, 실패해도 무관)
    Future(() async {
      try {
        final r = await _loc.getTodayLocations();
        if (mounted) _safeSetState(() => _records = r);
      } catch (_) {}
    });
    Future(() async {
      try {
        _places = _loc.knownPlaces;
        if (mounted) _safeSetState(() {});
      } catch (_) {}
    });
    Future(() async {
      try {
        final t = await _loc.getTimelineByDate(dateStr);
        if (mounted) _safeSetState(() => _timeline = t);
      } catch (_) {}
    });
    Future(() async {
      try {
        final s = await _loc.getPlaceSummaryByDate(dateStr);
        if (mounted) _safeSetState(() => _placeSummary = s);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('위치 추적', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        bottom: TabBar(
          controller: _tab,
          labelStyle: BotanicalTypo.label(size: 13, weight: FontWeight.w700),
          unselectedLabelStyle: BotanicalTypo.label(size: 13, weight: FontWeight.w500),
          indicatorSize: TabBarIndicatorSize.label,
          indicatorColor: _accent,
          labelColor: _accent,
          unselectedLabelColor: _textMuted,
          tabs: const [Tab(text: '오늘 현황'), Tab(text: '등록 장소'), Tab(text: '타임라인')],
        ),
      ),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: _accent))
        : TabBarView(controller: _tab, children: [
            _todayTab(), _placesTab(), _timelineTab()]),
    );
  }

  // ═══ TAB 1: 오늘 현황 ═══
  Widget _todayTab() {
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        _trackingToggle(),
        const SizedBox(height: 20),
        _placeSummaryCard(),
        const SizedBox(height: 20),
        _recentLocationsList(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _trackingToggle() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.libraryCard(),
      child: Row(children: [
        Container(width: 56, height: 56,
          decoration: BoxDecoration(
            color: _tracking
              ? BotanicalColors.subjectData.withOpacity(0.15)
              : BotanicalColors.surfaceDark,
            borderRadius: BorderRadius.circular(16)),
          child: Icon(
            _tracking ? Icons.location_on_rounded : Icons.location_off_rounded,
            color: _tracking ? BotanicalColors.subjectData : BotanicalColors.textMutedDark,
            size: 28)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GPS 위치 추적', style: BotanicalTypo.heading(
            size: 16, color: BotanicalColors.textMainDark)),
          const SizedBox(height: 2),
          Text(_tracking
            ? '${_loc.currentPlaceName ?? "추적 중"} · 5분 간격' : '비활성 상태',
            style: BotanicalTypo.label(size: 12,
              color: _tracking ? BotanicalColors.subjectData : BotanicalColors.textMutedDark)),
        ])),
        Switch(
          value: _tracking,
          onChanged: (v) async {
            if (v) { await _loc.startTracking(); } else { await _loc.stopTracking(); }
            _safeSetState(() => _tracking = _loc.isTracking);
          },
          activeColor: BotanicalColors.subjectData,
          inactiveTrackColor: BotanicalColors.surfaceDark,
        ),
      ]),
    );
  }

  /// F4: WiFi 기반 자동 GPS ON/OFF 토글
  Widget _placeSummaryCard() {
    if (_placeSummary.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BotanicalDeco.card(_dk),
        child: Column(children: [
          const Text('📍', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text('오늘 위치 기록이 없습니다', style: BotanicalTypo.body(size: 14, color: _textMuted)),
          const SizedBox(height: 4),
          Text('추적을 시작하면 장소별 체류시간이 표시됩니다',
            style: BotanicalTypo.label(size: 12, color: _textMuted)),
        ]),
      );
    }

    final entries = _placeSummary.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalMin = entries.fold<int>(0, (s, e) => s + e.value);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('장소별 체류시간', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BotanicalDeco.badge(_accent),
            child: Text('총 ${_formatMin(totalMin)}', style: BotanicalTypo.label(
              size: 11, weight: FontWeight.w700, color: _accent)),
          ),
        ]),
        const SizedBox(height: 16),
        ...entries.map((e) {
          final pct = totalMin > 0 ? e.value / totalMin : 0.0;
          final color = _placeColor(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(e.key, style: BotanicalTypo.body(size: 13, weight: FontWeight.w600, color: _textMain)),
                Text(_formatMin(e.value), style: BotanicalTypo.label(
                  size: 12, weight: FontWeight.w700, color: color)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: pct,
                  backgroundColor: _dk ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
                  valueColor: AlwaysStoppedAnimation(color), minHeight: 8)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _recentLocationsList() {
    if (_records.isEmpty) return const SizedBox();
    final recent = _records.length > 20 ? _records.sublist(_records.length - 20) : _records;

    // F5: 연속 동일 장소 병합
    final deduped = <LocationRecord>[];
    for (final r in recent) {
      if (deduped.isNotEmpty &&
          deduped.last.placeName == r.placeName &&
          deduped.last.placeName != null) {
        final prev = deduped.removeLast();
        deduped.add(LocationRecord(
          id: r.id, date: r.date, timestamp: r.timestamp,
          latitude: r.latitude, longitude: r.longitude,
          placeName: r.placeName, placeId: r.placeId,
          placeCategory: r.placeCategory, wifiSsid: r.wifiSsid,
          durationMinutes: r.durationMinutes > prev.durationMinutes
              ? r.durationMinutes : prev.durationMinutes,
        ));
      } else {
        deduped.add(r);
      }
    }

    final reversed = deduped.reversed.take(8).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.history_rounded, size: 16, color: _accent),
          const SizedBox(width: 8),
          Text('최근 동선', style: BotanicalTypo.body(size: 14, weight: FontWeight.w700, color: _textMain)),
          const Spacer(),
          Text('${reversed.length}건', style: BotanicalTypo.label(
            size: 11, weight: FontWeight.w600, color: _textMuted)),
        ]),
        const SizedBox(height: 16),
        ...reversed.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          final t = DateTime.tryParse(r.timestamp);
          final timeStr = t != null ? DateFormat('HH:mm').format(t) : '';
          final color = _placeColor(r.placeName ?? '');
          final isLast = i == reversed.length - 1;
          final name = r.placeName ?? '알 수 없는 장소';
          final emoji = _placeEmoji(r.placeCategory);

          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 시간
            SizedBox(width: 44, child: Text(timeStr, style: BotanicalTypo.label(
              size: 12, weight: FontWeight.w700, color: _textSub))),
            // 타임라인 선
            SizedBox(width: 24, child: Column(children: [
              Container(width: 10, height: 10,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2))),
              if (!isLast)
                Container(width: 1.5, height: 44,
                  color: _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight.withOpacity(0.6)),
            ])),
            const SizedBox(width: 8),
            // 카드
            Expanded(child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _dk ? color.withOpacity(0.06) : color.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(_dk ? 0.12 : 0.08))),
              child: Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: BotanicalTypo.body(
                    size: 13, weight: FontWeight.w600, color: _textMain),
                    overflow: TextOverflow.ellipsis),
                  if (r.wifiSsid != null)
                    Text('📶 ${r.wifiSsid}', style: BotanicalTypo.label(
                      size: 10, color: _textMuted)),
                ])),
                if (r.durationMinutes > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(_dk ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text('${r.durationMinutes}분', style: BotanicalTypo.label(
                      size: 10, weight: FontWeight.w700, color: color))),
              ]),
            )),
          ]);
        }),
      ]),
    );
  }

  String _placeEmoji(String? category) {
    switch (category) {
      case 'home': return '🏠';
      case 'library': return '📚';
      case 'cafe': return '☕';
      case 'school': return '🏫';
      case 'work': return '💼';
      case 'restaurant': return '🍽️';
      default: return '📍';
    }
  }

  // ═══ TAB 2: 등록 장소 ═══
  Widget _placesTab() {
    return ListView(padding: const EdgeInsets.all(20), children: [
      _addPlaceButton(),
      const SizedBox(height: 20),
      if (_places.isEmpty)
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BotanicalDeco.card(_dk),
          child: Column(children: [
            const Text('🗺️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('등록된 장소가 없습니다', style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 4),
            Text('자주 가는 장소를 등록하면\n자동으로 체류시간을 기록합니다',
              textAlign: TextAlign.center,
              style: BotanicalTypo.label(size: 12, color: _textMuted)),
          ]),
        ),
      ..._places.map((p) => _placeCard(p)),
    ]);
  }

  Widget _addPlaceButton() {
    return GestureDetector(
      onTap: () => _showAddPlaceSheet(),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [BotanicalColors.primary, BotanicalColors.primaryLight]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: BotanicalColors.primary.withOpacity(0.3),
            blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(width: 48, height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.add_location_alt_rounded, color: Colors.white, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('현재 위치 등록', style: BotanicalTypo.heading(size: 16, color: Colors.white)),
            Text('GPS 좌표 + WiFi 기반 자동 인식',
              style: BotanicalTypo.label(size: 12, color: Colors.white.withOpacity(0.7))),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  Widget _placeCard(KnownPlace p) {
    final cc = _categoryColor(p.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight),
      ),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BotanicalDeco.iconBox(cc, _dk, radius: 12),
          child: Center(child: Text(p.emoji, style: const TextStyle(fontSize: 20)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
          const SizedBox(height: 2),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cc.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(KnownPlace.categoryLabel(p.category), style: BotanicalTypo.label(
                size: 10, weight: FontWeight.w600, color: cc)),
            ),
            const SizedBox(width: 8),
            Text('반경 ${p.radiusMeters}m', style: BotanicalTypo.label(size: 10, color: _textMuted)),
            if (p.wifiSsid != null) ...[
              const SizedBox(width: 8),
              Text('📶 ${p.wifiSsid}', style: BotanicalTypo.label(
                size: 10, color: BotanicalColors.info)),
            ],
          ]),
        ])),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: BotanicalColors.error),
          onPressed: () async {
            final ok = await showDialog<bool>(context: context,
              builder: (c) => AlertDialog(
                title: Text('장소 삭제', style: BotanicalTypo.heading(size: 18)),
                content: Text('${p.name}을(를) 삭제하시겠습니까?', style: BotanicalTypo.body()),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text('취소', style: TextStyle(color: _textMuted))),
                  TextButton(onPressed: () => Navigator.pop(c, true),
                    child: const Text('삭제', style: TextStyle(color: BotanicalColors.error))),
                ]));
            if (ok == true) { await _loc.removeKnownPlace(p.id); _load(); }
          },
        ),
      ]),
    );
  }

  // ═══ TAB 3: 행동 타임라인 ═══
  Widget _timelineTab() {
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Column(children: [
      // N3: 날짜 선택기
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          GestureDetector(
            onTap: () {
              _safeSetState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
              _load();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _dk ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.chevron_left_rounded, size: 20, color: _textSub)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 90)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _safeSetState(() => _selectedDate = picked);
                  _load();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _dk ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text(
                  isToday
                    ? '오늘 (${DateFormat('M/d').format(_selectedDate)})'
                    : DateFormat('yyyy년 M월 d일 (E)', 'ko').format(_selectedDate),
                  style: BotanicalTypo.body(
                    size: 14, weight: FontWeight.w700, color: _textMain))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: isToday ? null : () {
              _safeSetState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
              _load();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _dk ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.chevron_right_rounded, size: 20,
                color: isToday ? _textMuted.withOpacity(0.3) : _textSub)),
          ),
        ]),
      ),

      // 타임라인 목록
      // F6: 리프레시 버튼 + 요약
      if (_timeline.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text('${_timeline.length}개 활동', style: BotanicalTypo.label(
              size: 11, color: _textMuted)),
            const SizedBox(width: 8),
            Text('체류 ${_totalStayMin()}분', style: BotanicalTypo.label(
              size: 11, weight: FontWeight.w700, color: _accent)),
            const Spacer(),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded, size: 14, color: _accent),
                  const SizedBox(width: 4),
                  Text('새로고침', style: BotanicalTypo.label(
                    size: 10, weight: FontWeight.w700, color: _accent)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ],
      Expanded(child: _timeline.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🕐', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(isToday ? '오늘 행동 타임라인이 없습니다' : '해당 날짜 기록이 없습니다',
              style: BotanicalTypo.body(size: 14, color: _textMuted)),
          ]))
        : _timelineList()),
    ]);
  }

  Widget _timelineList() {
    final sorted = List<BehaviorTimelineEntry>.from(_timeline)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: sorted.length,
      itemBuilder: (ctx, i) {
        final e = sorted[i];
        final start = DateTime.tryParse(e.startTime);
        final end = DateTime.tryParse(e.endTime);
        final startStr = start != null ? DateFormat('HH:mm').format(start) : '';
        final endStr = end != null ? DateFormat('HH:mm').format(end) : '';
        final color = _typeColor(e.type);

        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 52, child: Column(children: [
            Text(startStr, style: BotanicalTypo.label(size: 12, weight: FontWeight.w700, color: _textSub)),
            Text(endStr, style: BotanicalTypo.label(size: 10, color: _textMuted)),
          ])),
          Column(children: [
            Container(width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            if (i < sorted.length - 1)
              Container(width: 2, height: 60,
                color: _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: color, width: 3)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Text(e.emoji ?? '📍', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(e.label, style: BotanicalTypo.body(
                size: 13, weight: FontWeight.w600, color: _textMain))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(_formatMin(e.durationMinutes), style: BotanicalTypo.label(
                  size: 11, weight: FontWeight.w700, color: color)),
              ),
            ]),
          )),
        ]);
      },
    );
  }

  // ═══ 장소 등록 BottomSheet ═══

  /// F6: 총 체류시간 계산
  int _totalStayMin() => _timeline
    .where((e) => e.type == 'stay')
    .fold<int>(0, (s, e) => s + e.durationMinutes);

  void _showAddPlaceSheet() {
    String name = '';
    String category = 'library';
    String? wifi;
    int radius = 100;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: sheetBottomPad(ctx, extra: 24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: _textMuted, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('현재 위치 등록', style: BotanicalTypo.heading(size: 18, color: _textMain)),
            const SizedBox(height: 20),
            TextField(
              onChanged: (v) => name = v,
              decoration: InputDecoration(
                labelText: '장소 이름', hintText: '예: 국립중앙도서관',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                prefixIcon: const Icon(Icons.place_outlined)),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8,
              children: ['home', 'library', 'cafe', 'school', 'work', 'other'].map((cat) {
                final sel = category == cat;
                final c = _categoryColor(cat);
                return GestureDetector(
                  onTap: () => setBS(() => category = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: sel
                      ? BotanicalDeco.selectedChip(c, _dk, radius: 12)
                      : BotanicalDeco.unselectedChip(_dk, radius: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(KnownPlace.categoryEmoji(cat), style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(KnownPlace.categoryLabel(cat), style: BotanicalTypo.label(
                        size: 12, weight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? c : _textMain)),
                    ]),
                  ),
                );
              }).toList()),
            const SizedBox(height: 16),
            TextField(
              onChanged: (v) => wifi = v.isEmpty ? null : v,
              decoration: InputDecoration(
                labelText: 'WiFi SSID (선택)', hintText: '연결된 WiFi 이름',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                prefixIcon: const Icon(Icons.wifi)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('인식 반경', style: BotanicalTypo.body(size: 13, weight: FontWeight.w600, color: _textMain)),
              Expanded(child: Slider(
                value: radius.toDouble(), min: 50, max: 500, divisions: 9,
                label: '${radius}m',
                onChanged: (v) => setBS(() => radius = v.round()),
                activeColor: _accent)),
              Text('${radius}m', style: BotanicalTypo.body(
                size: 13, weight: FontWeight.w700, color: _accent)),
            ]),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: name.isNotEmpty ? () async {
                Navigator.pop(ctx);
                final place = await _loc.registerCurrentLocation(
                  name: name, category: category, wifiSsid: wifi, radiusMeters: radius);
                if (place != null) {
                  _load();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${place.emoji} $name 등록 완료')));
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('위치를 가져올 수 없습니다. GPS를 확인하세요.')));
                }
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: BotanicalColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0),
              child: Text('현재 위치로 등록', style: BotanicalTypo.heading(size: 16, color: Colors.white)),
            )),
          ]),
        );
      }),
    );
  }

  // ═══ 유틸리티 ═══
  String _formatMin(int min) {
    if (min < 60) return '${min}분';
    return '${min ~/ 60}시간 ${min % 60}분';
  }

  Color _placeColor(String name) {
    final colors = [
      BotanicalColors.subjectVerbal, BotanicalColors.subjectData,
      BotanicalColors.gold, BotanicalColors.error,
      BotanicalColors.info, BotanicalColors.subjectConst,
      BotanicalColors.warning, BotanicalColors.subjectEnglish,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'home': return BotanicalColors.gold;
      case 'library': return BotanicalColors.subjectVerbal;
      case 'cafe': return BotanicalColors.subjectConst;
      case 'school': return BotanicalColors.subjectData;
      case 'work': return BotanicalColors.info;
      default: return _textMuted;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'stay': return BotanicalColors.subjectVerbal;
      case 'travel': return BotanicalColors.warning;
      case 'location': return BotanicalColors.subjectVerbal;
      case 'focus': return BotanicalColors.subjectData;
      case 'app_usage': return BotanicalColors.error;
      case 'movement': return BotanicalColors.warning;
      default: return _textMuted;
    }
  }
}