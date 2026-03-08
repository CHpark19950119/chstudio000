import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';
import 'firebase_service.dart';
import 'telegram_service.dart';
import 'location_service.dart';

part 'nfc_action_part.dart';

/// NFC Action — UI에서 읽을 마지막 액션 정보
class NfcAction {
  final String action;
  final String emoji;
  final String message;
  NfcAction(this.action, this.emoji, this.message);
}

/// NFC 태그 서비스 — ChangeNotifier 싱글톤
/// 5 roles: wake / outing(toggle) / study(start/resume/end) / meal(toggle) / sleep
const _nfcChannel = MethodChannel('com.cheonhong.cheonhong_studio/nfc');

class NfcService extends ChangeNotifier {
  static final NfcService _instance = NfcService._internal();
  factory NfcService() => _instance;
  NfcService._internal();

  List<NfcTagConfig> _tags = [];
  bool _nfcAvailable = false;
  bool _initialized = false;

  bool _isOut = false;
  bool _isStudying = false;
  bool _isMealing = false;
  bool _silentReaderEnabled = false;
  bool _wasStudyingBeforeMeal = false;

  NfcAction? _lastAction;
  String lastDiagnostic = '';
  bool _notifPermissionRequested = false;

  bool get isAvailable => _nfcAvailable;
  List<NfcTagConfig> get tags => List.unmodifiable(_tags);
  bool get isOut => _isOut;
  bool get isStudying => _isStudying;
  bool get isMealing => _isMealing;
  bool get isSilentReaderEnabled => _silentReaderEnabled;

  NfcAction? consumeLastAction() {
    final a = _lastAction;
    _lastAction = null;
    return a;
  }

  void _emitAction(String action, String emoji, String message) {
    _lastAction = NfcAction(action, emoji, message);
    notifyListeners();
  }

  void forceOutState(bool value) {
    _isOut = value;
    _saveToggleState();
    notifyListeners();
  }

  void forceStudyState(bool value) {
    _isStudying = value;
    _saveToggleState();
    notifyListeners();
  }

  void _log(String msg) {
    debugPrint('[NFC] $msg');
    lastDiagnostic = '${DateFormat('HH:mm:ss').format(DateTime.now())} $msg';
  }

  String _studyDate([DateTime? dt]) => StudyDateUtils.todayKey(dt);

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) {
      _log('이미 초기화됨 — 스킵');
      return;
    }
    _log('초기화 시작');

    try {
      _nfcAvailable = await NfcManager.instance.isAvailable();
      _log('NFC 사용 가능: $_nfcAvailable');
    } catch (e) {
      _nfcAvailable = false;
      _log('NFC 가용성 체크 실패: $e');
    }

    await _loadTags();
    _log('태그 로드 완료: ${_tags.length}개');

    await _restoreToggleState();
    _log('토글 복원: isOut=$_isOut, isStudying=$_isStudying');

    _setupMethodChannel();

    try {
      await _nfcChannel.invokeMethod('flutterReady');
    } catch (e) {
      _log('flutterReady 전송 실패: $e');
    }

    // 대기 중인 NFC Intent 처리
    try {
      final pending = await _nfcChannel.invokeMethod<Map>('getPendingNfcIntent');
      if (pending != null) {
        final role = _argStr(pending, 'role');
        final tagUid = _argStr(pending, 'tagUid');
        _log('대기 Intent: role=$role, tagUid=$tagUid');
        if (role.isNotEmpty) {
          final parsed = NfcTagRole.values.where((r) => r.name == role);
          if (parsed.isNotEmpty) await _dispatch(parsed.first, tagUid: tagUid.isNotEmpty ? tagUid : null);
        } else if (tagUid.isNotEmpty) {
          final matched = _matchTag(tagUid);
          if (matched != null) await _dispatch(matched.role, tagUid: tagUid, tagName: matched.name);
        }
      }
    } catch (e) {
      _log('pendingNfcIntent 조회 실패: $e');
    }

    await _requestNotificationPermissionOnce();
    _initialized = true;
    _log('초기화 완료');
    notifyListeners();
  }

  Future<void> reloadTags() async {
    await _loadTags();
    _log('태그 리로드: ${_tags.length}개');
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  무진동 리더 모드
  // ═══════════════════════════════════════════

  Future<void> enableSilentReader() async {
    if (!_nfcAvailable) return;
    try {
      await _nfcChannel.invokeMethod('enableSilentReader');
      _silentReaderEnabled = true;
      _log('무진동 모드 ON');
      notifyListeners();
    } catch (e) {
      _log('enableSilentReader 에러: $e');
    }
  }

  Future<void> disableSilentReader() async {
    try {
      await _nfcChannel.invokeMethod('disableSilentReader');
      _silentReaderEnabled = false;
      _log('무진동 모드 OFF');
      notifyListeners();
    } catch (e) {
      _log('disableSilentReader 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  MethodChannel 리스너
  // ═══════════════════════════════════════════

  void _setupMethodChannel() {
    _nfcChannel.setMethodCallHandler((call) async {
      if (call.method != 'onNfcTagFromIntent') return;
      final args = call.arguments;
      final role = _argStr(args, 'role');
      final tagUid = _argStr(args, 'tagUid');
      _log('NFC Intent: role="$role", tagUid="$tagUid"');

      if (role.isNotEmpty) {
        final parsed = NfcTagRole.values.where((r) => r.name == role);
        if (parsed.isNotEmpty) {
          await _dispatch(parsed.first, tagUid: tagUid.isNotEmpty ? tagUid : null);
        } else {
          _log('알 수 없는 role: "$role"');
        }
      } else if (tagUid.isNotEmpty) {
        final matched = _matchTag(tagUid);
        if (matched != null) {
          await _dispatch(matched.role, tagUid: tagUid, tagName: matched.name);
        } else {
          _log('미등록 태그: $tagUid');
        }
      }
    });
  }

  String _argStr(dynamic args, String key) {
    try {
      if (args is Map) {
        final v = args[key];
        if (v != null) return v.toString();
      }
    } catch (_) {}
    return '';
  }

  // ═══════════════════════════════════════════
  //  Unified dispatch (replaces _executeRole + _handleAutoAction)
  // ═══════════════════════════════════════════

  Future<void> _dispatch(NfcTagRole role, {
    String? tagUid, String? tagName, bool saveEvent = true,
  }) async {
    final now = DateTime.now();
    final dateStr = _studyDate(now);
    final timeStr = DateFormat('HH:mm').format(now);

    if (saveEvent) {
      String? action;
      if (role == NfcTagRole.outing) action = _isOut ? 'end' : 'start';
      else if (role == NfcTagRole.study) {
        if (_isMealing || _isOut) action = 'resume';
        else action = _isStudying ? 'end' : 'start';
      }
      else if (role == NfcTagRole.meal) action = _isMealing ? 'end' : 'start';

      final event = NfcEvent(
        id: 'nfc_${now.millisecondsSinceEpoch}',
        date: dateStr, timestamp: now.toIso8601String(),
        role: role,
        tagName: tagName ?? _findTagName(tagUid) ?? role.name,
        action: action,
      );
      try { await FirebaseService().saveNfcEvent(dateStr, event); }
      catch (e) { _log('이벤트 저장 실패: $e'); }
    }

    switch (role) {
      case NfcTagRole.wake:
        await _handleWake(dateStr, timeStr);
        break;
      case NfcTagRole.outing:
        await _handleOutingToggle(dateStr, timeStr);
        break;
      case NfcTagRole.study:
        await _handleStudyToggle(dateStr, timeStr);
        break;
      case NfcTagRole.sleep:
        await _handleSleep(dateStr, timeStr);
        break;
      case NfcTagRole.meal:
        await _handleMealToggle(dateStr, timeStr);
        break;
    }
    notifyListeners();
  }

  /// 수동 테스트 (NFC 하드웨어 우회)
  Future<String> manualTestRole(NfcTagRole role) async {
    _log('수동 테스트: ${role.name}');
    try {
      await _dispatch(role, saveEvent: false);
      return '${role.name} 실행 성공 (isOut=$_isOut, isStudying=$_isStudying)';
    } catch (e) {
      return '에러: $e';
    }
  }

  String? _findTagName(String? uid) {
    if (uid == null) return null;
    for (final t in _tags) {
      if (t.nfcId?.toLowerCase() == uid.toLowerCase()) return t.name;
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  NFC 태그 스캔 (수동, NFC 화면용)
  // ═══════════════════════════════════════════

  Future<void> startScan({
    required Function(NfcTagConfig? matchedTag, String nfcUid) onDetected,
    required Function(String error) onError,
    bool executeOnMatch = true,
  }) async {
    if (!_nfcAvailable) {
      onError('NFC를 사용할 수 없습니다');
      return;
    }
    if (_silentReaderEnabled) await disableSilentReader();

    try { NfcManager.instance.stopSession(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        try {
          final uid = _extractUid(tag);
          if (uid == null) {
            onError('태그 UID를 읽을 수 없습니다');
            NfcManager.instance.stopSession();
            return;
          }
          final matched = _matchTag(uid);
          onDetected(matched, uid);
          if (executeOnMatch && matched != null) {
            await _dispatch(matched.role, tagUid: uid, tagName: matched.name);
          }
          NfcManager.instance.stopSession();
        } catch (e) {
          onError('태그 읽기 실패: $e');
          NfcManager.instance.stopSession();
        }
      },
    );
  }

  void stopScan() {
    try { NfcManager.instance.stopSession(); } catch (_) {}
  }

  String? _extractUid(NfcTag tag) {
    try {
      final data = tag.data;
      for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv', 'mifareclassic', 'mifareultralight']) {
        final tech = data[key];
        if (tech != null && tech is Map) {
          final id = tech['identifier'];
          if (id != null && id is List) {
            return id.cast<int>()
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(':');
          }
        }
      }
    } catch (e) {
      _log('UID 추출 실패: $e');
    }
    return null;
  }

  NfcTagConfig? _matchTag(String uid) {
    for (final t in _tags) {
      if (t.nfcId != null && t.nfcId!.toLowerCase() == uid.toLowerCase()) return t;
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  NDEF 쓰기
  // ═══════════════════════════════════════════

  Future<bool> writeNdefToTag({
    required NfcTagRole role,
    required String tagId,
    required Function(String) onStatus,
  }) async {
    if (!_nfcAvailable) return false;
    if (_silentReaderEnabled) await disableSilentReader();

    try { NfcManager.instance.stopSession(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));

    final completer = Completer<bool>();
    onStatus('태그를 가까이 대세요...');

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        try {
          final uri = 'cheonhong://nfc?role=${role.name}&tagId=$tagId';
          final uriRecord = NdefRecord.createUri(Uri.parse(uri));
          final aarRecord = NdefRecord(
            typeNameFormat: NdefTypeNameFormat.nfcExternal,
            type: Uint8List.fromList('android.com:pkg'.codeUnits),
            identifier: Uint8List(0),
            payload: Uint8List.fromList('com.cheonhong.cheonhong_studio'.codeUnits),
          );
          final message = NdefMessage([uriRecord, aarRecord]);

          bool written = false;
          final ndef = Ndef.from(tag);
          if (ndef != null) {
            if (ndef.isWritable) {
              await ndef.write(message);
              written = true;
            } else {
              onStatus('태그가 쓰기 금지 상태입니다');
            }
          } else {
            onStatus('NDEF 미지원 태그입니다');
          }

          NfcManager.instance.stopSession();
          if (written) onStatus('NDEF 쓰기 완료!');
          if (!completer.isCompleted) completer.complete(written);
        } catch (e) {
          NfcManager.instance.stopSession(errorMessage: 'NDEF 쓰기 실패');
          onStatus('쓰기 실패: $e');
          if (!completer.isCompleted) completer.complete(false);
        }
      },
      onError: (error) async {
        onStatus('NFC 세션 오류');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        try { NfcManager.instance.stopSession(); } catch (_) {}
        onStatus('시간 초과');
        completer.complete(false);
      }
    });

    return completer.future;
  }

  // ═══════════════════════════════════════════
  //  태그 CRUD
  // ═══════════════════════════════════════════

  Future<NfcTagConfig> registerTag({
    required String name,
    required NfcTagRole role,
    required String nfcUid,
    String? placeName,
  }) async {
    final tag = NfcTagConfig(
      id: 'nfc_tag_${DateTime.now().millisecondsSinceEpoch}',
      name: name, role: role, nfcId: nfcUid,
      placeName: placeName,
      createdAt: DateTime.now().toIso8601String(),
    );
    _tags.add(tag);
    await FirebaseService().saveNfcTags(_tags);
    notifyListeners();
    return tag;
  }

  Future<void> removeTag(String tagId) async {
    _tags.removeWhere((t) => t.id == tagId);
    await FirebaseService().saveNfcTags(_tags);
    notifyListeners();
  }

  Future<void> updateTagRole(String tagId, NfcTagRole newRole) async {
    final idx = _tags.indexWhere((t) => t.id == tagId);
    if (idx < 0) return;
    final old = _tags[idx];
    _tags[idx] = NfcTagConfig(
      id: old.id, name: old.name, role: newRole,
      nfcId: old.nfcId, placeName: old.placeName,
      createdAt: old.createdAt,
    );
    await FirebaseService().saveNfcTags(_tags);
    notifyListeners();
  }

  Future<void> _loadTags() async {
    try { _tags = await FirebaseService().getNfcTags(); }
    catch (_) { _tags = []; }
  }

  // ═══════════════════════════════════════════
  //  토글 상태 저장/복원
  // ═══════════════════════════════════════════

  Future<void> _saveToggleState() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = _studyDate();
    await prefs.setBool('nfc_is_out', _isOut);
    await prefs.setBool('nfc_is_studying', _isStudying);
    await prefs.setBool('nfc_is_mealing', _isMealing);
    await prefs.setBool('nfc_was_studying_before_meal', _wasStudyingBeforeMeal);
    await prefs.setString('nfc_toggle_date', dateStr);
  }

  Future<void> _restoreToggleState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('nfc_toggle_date');
    final today = _studyDate();
    if (savedDate == today) {
      _isOut = prefs.getBool('nfc_is_out') ?? false;
      _isStudying = prefs.getBool('nfc_is_studying') ?? false;
      _isMealing = prefs.getBool('nfc_is_mealing') ?? false;
      _wasStudyingBeforeMeal = prefs.getBool('nfc_was_studying_before_meal') ?? false;
    } else {
      _isOut = false;
      _isStudying = false;
      _isMealing = false;
      _wasStudyingBeforeMeal = false;
      await _saveToggleState();
    }
  }

  // ═══════════════════════════════════════════
  //  이동시간 요약
  // ═══════════════════════════════════════════

  Future<Map<String, int?>> getTodayTravelSummary() async {
    final dateStr = _studyDate();
    try {
      final records = await FirebaseService().getTimeRecords();
      final tr = records[dateStr];
      if (tr == null) return {};
      return {
        'commuteTo': tr.commuteToMinutes,
        'commuteFrom': tr.commuteFromMinutes,
        'stayTime': tr.stayMinutes,
      };
    } catch (_) {
      return {};
    }
  }
}
