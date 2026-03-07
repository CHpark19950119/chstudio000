import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'firebase_service.dart';
import 'weather_service.dart';
import 'ai_calendar_service.dart';
import 'sleep_service.dart';

/// 음성 브리핑 서비스 (#11)
/// 책상 NFC 태깅 시 자동 실행 — 날씨 + 어제 성적 + 오늘 할 일 TTS
///
/// v8.12: UL-3+8 — 무음모드 복구 완전 보장
///   - 정상종료, 에러, 취소, 타임아웃, 앱 백그라운드 모든 경로에서 복구
///   - 안전 타이머: 3분 후 강제 복구 (최후 보루)
///   - _volumePending 플래그로 중복 복구 방지
class BriefingService {
  static final BriefingService _instance = BriefingService._internal();
  factory BriefingService() => _instance;
  BriefingService._internal();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _isSpeaking = false;

  // 볼륨 제어 채널
  static const _volumeChannel = MethodChannel('com.cheonhong.cheonhong_studio/volume');
  int? _savedVolume;
  int? _savedRingerMode;
  bool _volumePending = false; // ★ UL-3: 볼륨 복구 대기 중 플래그
  Timer? _safetyTimer; // ★ UL-8: 안전 타이머

  bool get isSpeaking => _isSpeaking;

  /// ★ UL-8: 앱 resume 시 호출 — 볼륨 미복구 상태면 강제 복구
  Future<void> ensureVolumeRestored() async {
    if (_volumePending) {
      debugPrint('[Briefing] ⚠️ 앱 resume — 미복구 볼륨 감지 → 강제 복구');
      await _restoreVolume();
    }
  }

  // ─── TTS 엔진 준비 ───
  Future<bool> _ensureTtsReady() async {
    try {
      _tts ??= FlutterTts();
      final tts = _tts!;

      final engines = await tts.getEngines;
      if (engines == null || (engines as List).isEmpty) {
        debugPrint('[Briefing] ❌ TTS 엔진 없음!');
        return false;
      }

      await tts.setLanguage('ko-KR');
      await tts.setSpeechRate(0.45);  // N3: 약간 더 천천히 (자연스러운 톤)
      await tts.setVolume(1.0);
      await tts.setPitch(1.05);  // N3: 약간 높은 톤 (밝은 느낌)
      await tts.awaitSpeakCompletion(true);

      // N3: Google TTS 엔진 우선 사용 (더 자연스러운 음성)
      try {
        final engines = await tts.getEngines;
        if (engines != null) {
          final engineList = engines as List;
          final googleEngine = engineList.firstWhere(
            (e) => e.toString().contains('google'),
            orElse: () => null,
          );
          if (googleEngine != null) {
            await tts.setEngine(googleEngine.toString());
            debugPrint('[Briefing] ✅ Google TTS 엔진 설정');
          }
        }
      } catch (e) {
        debugPrint('[Briefing] ⚠️ 엔진 설정 실패 (기본 사용): $e');
      }

      tts.setCompletionHandler(() {
        debugPrint('[Briefing] ✅ TTS 재생 완료');
        _isSpeaking = false;
        // ★ UL-3: completion에서도 복구 시도 (finally와 중복 OK — _volumePending 체크)
        _restoreVolume();
      });
      tts.setErrorHandler((msg) {
        debugPrint('[Briefing] ❌ TTS error: $msg');
        _isSpeaking = false;
        // ★ UL-8: 에러 시에도 복구
        _restoreVolume();
      });
      tts.setCancelHandler(() {
        debugPrint('[Briefing] ⏹️ TTS 취소됨');
        _isSpeaking = false;
        // ★ UL-8: 취소(중간 끊김) 시에도 복구
        _restoreVolume();
      });

      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('[Briefing] ❌ TTS 초기화 실패: $e');
      _initialized = false;
      return false;
    }
  }

  // ─── 볼륨 최대화 (무음/진동 모드 우회) ───
  Future<void> _boostVolume() async {
    try {
      _savedVolume = await _volumeChannel.invokeMethod<int>('getVolume');
      _savedRingerMode = await _volumeChannel.invokeMethod<int>('getRingerMode');
      final maxVol = await _volumeChannel.invokeMethod<int>('getMaxVolume') ?? 15;

      debugPrint('[Briefing] 🔊 볼륨 부스트: 현재=$_savedVolume, max=$maxVol, ringer=$_savedRingerMode');

      // 벨소리모드를 NORMAL로 (무음/진동 해제)
      await _volumeChannel.invokeMethod('setRingerMode', {'mode': 2});

      // 미디어 볼륨 80%로
      final targetVol = (maxVol * 0.8).round();
      await _volumeChannel.invokeMethod('setVolume', {'volume': targetVol});

      // ★ UL-3: 복구 대기 플래그 설정
      _volumePending = true;

      // ★ UL-8: 안전 타이머 — 3분 후 강제 복구 (최후 보루)
      _safetyTimer?.cancel();
      _safetyTimer = Timer(const Duration(minutes: 3), () {
        if (_volumePending) {
          debugPrint('[Briefing] ⚠️ 안전 타이머 만료 — 볼륨 강제 복구');
          _restoreVolume();
          _isSpeaking = false;
          try { _tts?.stop(); } catch (_) {}
        }
      });

      debugPrint('[Briefing] ✅ 볼륨 설정: $targetVol/$maxVol + 안전타이머 3분');
    } catch (e) {
      debugPrint('[Briefing] ⚠️ 볼륨 부스트 실패 (채널 미구현?): $e');
    }
  }

  // ─── 볼륨 복원 → 최소화 + 진동 OFF (모든 경로에서 안전하게 호출 가능) ───
  Future<void> _restoreVolume() async {
    // ★ UL-3: 이미 복원된 경우 스킵 (중복 호출 방지)
    if (!_volumePending) {
      debugPrint('[Briefing] 🔇 이미 복원됨 (스킵)');
      return;
    }

    // 먼저 상태 클리어 (재진입 방지)
    _savedVolume = null;
    _savedRingerMode = null;
    _volumePending = false;
    _safetyTimer?.cancel();
    _safetyTimer = null;

    // TTS 오디오 스트림이 완전히 해제될 때까지 대기
    await Future.delayed(const Duration(milliseconds: 300));

    // ★ UL-3 FIX: 복원 대신 음량 최소화 + 진동 OFF (무음 모드)
    // 1단계: 미디어 볼륨 최소 (1)
    try {
      await _volumeChannel.invokeMethod('setVolume', {'volume': 1});
      debugPrint('[Briefing] 🔊 볼륨 → 최소(1)');
    } catch (e) {
      debugPrint('[Briefing] ⚠️ 볼륨 최소화 실패: $e');
    }

    // 2단계: 벨소리 모드 → 무음 (0=무음, 진동 OFF)
    try {
      await _volumeChannel.invokeMethod('setRingerMode', {'mode': 0});
      debugPrint('[Briefing] 🔔 벨모드 → 무음(0)');
    } catch (e) {
      debugPrint('[Briefing] ⚠️ 벨모드 설정 실패: $e');
    }
  }

  // ─── 모닝 브리핑 실행 ───
  Future<void> playMorningBriefing() async {
    debugPrint('[Briefing] ═══ 모닝 브리핑 시작 ═══');

    final ready = await _ensureTtsReady();
    if (!ready) {
      debugPrint('[Briefing] ❌ TTS 준비 실패');
      return;
    }

    // 볼륨 자동 최대화
    await _boostVolume();

    // ★ #5b: 배경음 시작
    await _startBgm();

    // ★ FIX: try/finally로 볼륨 복원 보장 + 타임아웃 안전장치
    try {
      final text = await _buildBriefingText();
      if (text.isEmpty) {
        await _speakSafe('좋은 아침입니다. 오늘도 화이팅.')
            .timeout(const Duration(seconds: 30), onTimeout: () {
          debugPrint('[Briefing] ⏰ TTS 타임아웃 (30초)');
          _tts?.stop();
        });
      } else {
        await _speakSafe(text)
            .timeout(const Duration(seconds: 120), onTimeout: () {
          debugPrint('[Briefing] ⏰ TTS 타임아웃 (120초)');
          _tts?.stop();
        });
      }
    } catch (e) {
      debugPrint('[Briefing] ❌ 브리핑 실행 오류: $e');
    } finally {
      // ★ 볼륨 복원 — 유일한 복원 경로 (핸들러에서 제거됨)
      _isSpeaking = false;
      await _stopBgm();
      await _restoreVolume();
      debugPrint('[Briefing] ✅ 브리핑 종료 — 볼륨 복원 완료');
    }
  }

  Future<void> _speakSafe(String text) async {
    try {
      _isSpeaking = true;
      await _tts?.speak(text);
    } catch (e) {
      debugPrint('[Briefing] ❌ TTS speak 에러: $e');
      _isSpeaking = false;

      try {
        _tts = null;
        _initialized = false;
        final retry = await _ensureTtsReady();
        if (retry) {
          _isSpeaking = true;
          await _tts?.speak(text);
        }
      } catch (e2) {
        debugPrint('[Briefing] ❌ TTS 재시도 실패: $e2');
        _isSpeaking = false;
        // ★ 볼륨 복원은 finally 블록에서 처리
      }
    }
  }

  Future<void> stop() async {
    try { await _tts?.stop(); } catch (_) {}
    _isSpeaking = false;
    await _stopBgm();
    await _restoreVolume(); // ★ UL-8: 수동 stop에서도 확실히 복구
  }

  // ─── #5b: 배경음 제어 ───
  Future<void> _startBgm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bgm = prefs.getString('briefing_bgm') ?? 'none';
      if (bgm == 'none') return;
      debugPrint('[Briefing] 🎵 배경음 시작: $bgm');
      await _volumeChannel.invokeMethod('startBriefingBgm', {'bgm': bgm});
    } catch (e) {
      debugPrint('[Briefing] ⚠️ 배경음 시작 실패 (native 미구현?): $e');
    }
  }

  Future<void> _stopBgm() async {
    try {
      await _volumeChannel.invokeMethod('stopBriefingBgm');
      debugPrint('[Briefing] 🎵 배경음 정지');
    } catch (e) {
      debugPrint('[Briefing] ⚠️ 배경음 정지 실패: $e');
    }
  }

  // ─── 브리핑 텍스트 구성 ───
  Future<String> _buildBriefingText() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final yesterday = DateFormat('yyyy-MM-dd').format(
      now.subtract(const Duration(days: 1)));
    final dayOfWeek = _koreanDayOfWeek(now.weekday);

    final parts = <String>[];

    // 1. 인사 + 아침 동기부여 멘트 (날짜 기반 로테이션)
    final greetings = [
      '좋은 아침입니다. 오늘도 성장하는 하루를 시작합시다.',
      '일어나셨군요. 새벽에 일어나는 사람이 세상을 바꿉니다.',
      '좋은 아침입니다. 어제의 나보다 오늘 한 걸음 더 나아가봅시다.',
      '기상 완료. 남들이 자는 이 시간, 당신은 이미 앞서가고 있습니다.',
      '좋은 아침입니다. 포기하고 싶을 때가 가장 가까이 온 순간입니다.',
      '오늘도 일어나 주셨네요. 꾸준함이 재능을 이깁니다.',
      '좋은 아침입니다. 오늘 하루는 미래의 나에게 보내는 선물입니다.',
      '기상 완료. 아침형 인간이 세상을 지배합니다.',
      '좋은 아침입니다. 하루를 지배하는 사람이 인생을 지배합니다.',
      '일어나셨군요. 결국 해내는 사람은 매일 아침 일어나는 사람입니다.',
      '좋은 아침입니다. 오늘의 노력이 내일의 실력이 됩니다.',
      '기상 완료. 시작이 반이라고 했습니다. 이미 반을 해냈습니다.',
      '좋은 아침입니다. 지금 흘리는 땀이 합격의 눈물로 돌아옵니다.',
      '일어나셨군요. 매일 조금씩, 하지만 절대 멈추지 마세요.',
      '좋은 아침입니다. 오늘도 묵묵히 자기 할 일을 합시다.',
      '기상 완료. 남들이 쉴 때 공부한 시간이 결과를 만듭니다.',
      '좋은 아침입니다. 당신의 노력을 아는 사람은 바로 당신 자신입니다.',
      '일어나셨군요. 어려운 일을 매일 하면 결국 쉬워집니다.',
      '좋은 아침입니다. 공부는 배신하지 않습니다. 오늘도 믿고 달립시다.',
      '기상 완료. 합격하는 그 날을 상상하며, 오늘도 최선을 다합시다.',
      '좋은 아침입니다. 1퍼센트의 매일이 365퍼센트의 성장을 만듭니다.',
      '일어나셨군요. 이 아침의 의지가 미래를 바꿉니다.',
      '좋은 아침입니다. 지금 이 순간이 가장 젊은 순간입니다.',
      '기상 완료. 고통은 잠깐이지만, 포기는 영원합니다.',
      '좋은 아침입니다. 오늘 하루가 모여 당신의 인생이 됩니다.',
      '일어나셨군요. 누군가는 당신의 자리를 원합니다. 뺏기지 맙시다.',
      '좋은 아침입니다. 늦었다고 생각할 때가 진짜 시작할 때입니다.',
      '기상 완료. 습관이 운명을 만듭니다. 오늘도 루틴을 지킵시다.',
      '좋은 아침입니다. 세상에서 가장 확실한 투자는 자기 자신입니다.',
      '일어나셨군요. 지금의 고생이 평생의 자유를 만듭니다.',
      '좋은 아침입니다. 준비된 사람에게 기회가 찾아옵니다.',
    ];
    final greetIdx = now.day + now.month * 31; // 매일 다른 멘트
    parts.add('${now.month}월 ${now.day}일 ${dayOfWeek}요일.');
    parts.add(greetings[greetIdx % greetings.length]);

    // 요일별 추가 멘트
    if (now.weekday == DateTime.monday) {
      parts.add('월요일입니다. 이번 주의 목표를 세우고 힘차게 시작합시다.');
    } else if (now.weekday == DateTime.friday) {
      parts.add('금요일입니다. 주말 전 마지막 평일, 알차게 보냅시다.');
    } else if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      parts.add('주말이지만 합격하는 사람은 주말에도 공부합니다. 남들과의 차이는 여기서 벌어집니다.');
    }

    // 2. 날씨
    try {
      final weather = await WeatherService().getCurrentWeather()
          .timeout(const Duration(seconds: 5));
      if (weather != null) {
        parts.add('오늘 날씨. ${weather.briefingSummary}');
        if (WeatherService().needsUmbrella(weather)) parts.add('우산을 챙기세요.');
        parts.add(WeatherService().getClothingAdvice(weather));
      }
    } catch (_) {}

    // 3. D-day
    try {
      final examDate = DateTime(2026, 3, 7);
      final dDay = examDate.difference(now).inDays;
      if (dDay > 0) {
        parts.add('시험까지 D 마이너스 $dDay일.');
        if (dDay <= 3) {
          parts.add('최종 점검 단계입니다. 새로운 문제보다 기출 복습에 집중하세요. 컨디션이 곧 실력입니다.');
        } else if (dDay <= 7) {
          parts.add('마지막 일주일. 여기서 포기하면 지금까지의 노력이 물거품이 됩니다. 끝까지 갑시다.');
        } else if (dDay <= 14) {
          parts.add('2주 남았습니다. 약점 과목을 집중 보강하세요. 지금 넓히는 것보다 깊이를 다지세요.');
        } else if (dDay <= 30) {
          parts.add('한 달 남짓. 체력과 멘탈 관리가 중요한 시기입니다.');
        }
      } else if (dDay == 0) {
        parts.add('오늘이 시험 당일입니다. 지금까지 준비한 것을 믿으세요. 당신은 충분히 준비되었습니다. 화이팅.');
      }
    } catch (_) {}

    // 4. 수면
    try {
      final sleepGrade = await SleepService().getSleepGrade(yesterday);
      if (sleepGrade != null) {
        final score = sleepGrade.totalScore.round();
        if (score >= 80) {
          parts.add('어젯밤 수면 $score점, ${sleepGrade.grade}등급. 컨디션 좋을 겁니다. 오늘 최대 효율을 뽑아봅시다.');
        } else if (score >= 60) {
          parts.add('수면 $score점. 괜찮습니다. 카페인을 적당히 활용하고, 낮잠 대신 스트레칭으로 컨디션을 올립시다.');
        } else {
          parts.add('수면 $score점으로 부족합니다. 그래도 일어난 것만으로 대단합니다. 오늘은 일찍 자도록 합시다.');
        }
      }
    } catch (_) {}

    // 5. 어제 성적 + 주간 트렌드
    try {
      final fb = FirebaseService();
      final timeRecords = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final studyRecords = await fb.getStudyTimeRecords().timeout(const Duration(seconds: 5));
      final yesterdayTR = timeRecords[yesterday];
      final yesterdaySR = studyRecords[yesterday];

      if (yesterdaySR != null && yesterdaySR.effectiveMinutes > 0) {
        final grade = DailyGrade.calculate(
          date: yesterday, wakeTime: yesterdayTR?.wake,
          studyStartTime: yesterdayTR?.study,
          effectiveMinutes: yesterdaySR.effectiveMinutes);
        final hours = yesterdaySR.effectiveMinutes ~/ 60;
        final mins = yesterdaySR.effectiveMinutes % 60;
        parts.add('어제 순공 ${hours}시간${mins > 0 ? ' $mins분' : ''}. '
            '${grade.totalScore.round()}점, ${grade.grade}등급.');

        if (yesterdaySR.effectiveMinutes >= 480) {
          parts.add('8시간 이상 공부했습니다. 대단합니다. 이 페이스를 유지합시다.');
        } else if (yesterdaySR.effectiveMinutes >= 360) {
          parts.add('6시간 이상. 좋은 흐름입니다. 조금만 더 올려봅시다.');
        }

        int weekTotal = 0, weekDays = 0;
        for (int i = 1; i <= 7; i++) {
          final d = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)));
          final sr = studyRecords[d];
          if (sr != null && sr.effectiveMinutes > 0) {
            weekTotal += sr.effectiveMinutes;
            weekDays++;
          }
        }
        if (weekDays >= 3) {
          final weekAvg = weekTotal ~/ weekDays;
          if (yesterdaySR.effectiveMinutes > weekAvg + 60) {
            parts.add('주간 평균보다 1시간 이상 많이 공부했습니다. 성장하고 있습니다.');
          } else if (yesterdaySR.effectiveMinutes > weekAvg) {
            parts.add('주간 평균 이상을 달성했습니다.');
          } else if (yesterdaySR.effectiveMinutes < weekAvg - 60) {
            parts.add('주간 평균에 비해 부족했습니다. 오늘 만회합시다. 어제는 이미 지나갔습니다.');
          }
        }

        // 연속일 체크
        int streak = 0;
        for (int i = 1; i <= 30; i++) {
          final d = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: i)));
          final sr = studyRecords[d];
          if (sr != null && sr.effectiveMinutes >= 60) streak++; else break;
        }
        if (streak >= 7) {
          parts.add('$streak일 연속 공부 중입니다. 놀라운 의지력입니다. 계속 갑시다.');
        } else if (streak >= 3) {
          parts.add('$streak일 연속 공부 중. 습관이 만들어지고 있습니다.');
        }
      } else {
        parts.add('어제 학습 기록이 없습니다. 괜찮습니다. 오늘부터 다시 시작하면 됩니다. 포기만 하지 맙시다.');
      }
    } catch (_) {}

    // 6. 기상시간
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 3));
      final todayTR = records[today];
      if (todayTR?.wake != null) {
        final wp = todayTR!.wake!.split(':');
        final h = int.parse(wp[0]);
        final m = int.parse(wp[1]);
        if (h < 6) parts.add('${h}시 ${m}분 기상. 새벽부터 일어나다니, 정말 대단합니다.');
        else if (h < 7) parts.add('${h}시 ${m}분 기상. 일찍 일어났습니다. 하루를 지배할 준비가 됐습니다.');
        else if (h == 7 && m <= 30) parts.add('${h}시 ${m}분 기상. 좋은 시작입니다. 이 타이밍을 유지합시다.');
        else parts.add('${h}시 ${m}분 기상. 늦었지만, 일어난 것 자체가 승리입니다. 내일은 더 일찍 도전합시다.');
      }
    } catch (_) {}

    // 7. 캘린더 + 일정 + 메모
    try {
      final dashboard = await AiCalendarService().getDashboard()
          .timeout(const Duration(seconds: 5));

      if (dashboard.todayEvents.isNotEmpty) {
        final events = dashboard.todayEvents.where((e) => e.type != EventType.exam)
            .map((e) => e.title).toList();
        if (events.isNotEmpty) parts.add('오늘 일정. ${events.join(', ')}.');
      }

      final upcoming = dashboard.upcomingEvents
          .where((e) => e.dDay != null && e.dDay! > 0 && e.dDay! <= 7)
          .toList();
      if (upcoming.isNotEmpty) {
        parts.add('이번 주 다가오는 일정.');
        for (final e in upcoming.take(5)) {
          final tag = e.importance == EventImportance.critical ? '중요, ' : '';
          parts.add('$tag${e.title}, ${e.dDay}일 후.');
        }
      }

      if (dashboard.memos.isNotEmpty) {
        parts.add('오늘의 메모.');
        for (final memo in dashboard.memos.take(2)) parts.add(memo);
      }
    } catch (_) {}

    // 8. 마무리 (로테이션)
    final closings = [
      '오늘도 집중해서 공부합시다. 화이팅.',
      '자, 이제 준비하고 출발합시다. 오늘의 나를 응원합니다.',
      '좋습니다. 오늘도 한 발짝 전진합시다. 당신은 할 수 있습니다.',
      '브리핑 끝. 이제 실행만 남았습니다. 오늘 하루도 파이팅.',
      '오늘의 계획을 실천합시다. 작은 성취가 큰 결과를 만듭니다.',
      '자, 시작합시다. 미래의 당신이 지금의 당신에게 감사할 겁니다.',
      '브리핑 완료. 세상에서 가장 확실한 투자, 바로 공부입니다. 화이팅.',
    ];
    parts.add(closings[greetIdx % closings.length]);

    return parts.join(' ');
  }

  Future<void> speak(String text) async {
    final ready = await _ensureTtsReady();
    if (!ready) return;
    await _boostVolume();
    try {
      await _speakSafe(text)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        debugPrint('[Briefing] ⏰ speak 타임아웃');
        _tts?.stop();
      });
    } finally {
      _isSpeaking = false;
      await _restoreVolume();
    }
  }

  String _koreanDayOfWeek(int weekday) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[weekday - 1];
  }

  Future<String> getBriefingText() async => await _buildBriefingText();
}