import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/botanical_theme.dart';
import '../services/weather_service.dart';
import '../services/nfc_service.dart';
import '../services/alarm_service.dart';
import '../services/sleep_service.dart';
import '../services/magnet_service.dart';
import '../models/models.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — 설정 화면
/// ═══════════════════════════════════════════════════════════
/// - Weather API 키 입력 (B6 Fix)
/// - 알람 배터리 최적화 상태
/// - NFC 무진동 기본값
/// - 다크모드 토글

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _weather = WeatherService();
  final _nfc = NfcService();
  final _sleepSvc = SleepService();
  final _apiKeyController = TextEditingController();

  bool _loading = true;
  bool _hasValidKey = false;
  bool _batteryExempt = false;
  bool _silentNfc = false;
  bool _saving = false;
  SleepSettings _sleepSettings = SleepSettings();
  String _briefingBgm = 'none';
  bool _magnetEnabled = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  static const _alarmChannel = MethodChannel('com.cheonhong.cheonhong_studio/alarm');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
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

  Future<void> _loadSettings() async {
    final key = await _weather.getApiKey();
    _hasValidKey = await _weather.hasValidApiKey();
    _silentNfc = _nfc.isSilentReaderEnabled;
    _sleepSettings = _sleepSvc.settings;

    try {
      _batteryExempt = await _alarmChannel.invokeMethod('isBatteryOptExempt') ?? false;
    } catch (_) {
      _batteryExempt = false;
    }

    if (key != null && key.isNotEmpty && key != 'YOUR_OPENWEATHERMAP_API_KEY') {
      _apiKeyController.text = key;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _briefingBgm = prefs.getString('briefing_bgm') ?? 'none';
    } catch (_) {}

    _magnetEnabled = MagnetService().isEnabled;

    _safeSetState(() => _loading = false);
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    _safeSetState(() => _saving = true);
    await _weather.setApiKey(key);
    final valid = await _weather.hasValidApiKey();

    // 테스트 호출
    final result = await _weather.getCurrentWeather();
    if (mounted) {
      _safeSetState(() {
        _hasValidKey = result != null;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result != null
            ? '✅ API 키 저장 완료 — 날씨: ${result.description}'
            : '❌ API 키가 유효하지 않습니다. 키를 확인하세요.'),
        backgroundColor: result != null ? BotanicalColors.primary : BotanicalColors.error,
      ));
    }
  }

  Future<void> _requestBatteryExemption() async {
    try {
      await _alarmChannel.invokeMethod('requestBatteryOptExemption');
      // 잠시 후 상태 재확인
      await Future.delayed(const Duration(seconds: 2));
      final exempt = await _alarmChannel.invokeMethod('isBatteryOptExempt') ?? false;
      _safeSetState(() => _batteryExempt = exempt);
    } catch (e) {
      debugPrint('[Settings] Battery exemption error: $e');
    }
  }

  Future<void> _toggleSilentNfc(bool value) async {
    if (value) {
      await _nfc.enableSilentReader();
    } else {
      await _nfc.disableSilentReader();
    }
    _safeSetState(() => _silentNfc = _nfc.isSilentReaderEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('설정', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _textMain,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionTitle('☁️ 날씨 API 설정'),
                const SizedBox(height: 8),
                _weatherApiCard(),
                const SizedBox(height: 24),

                _sectionTitle('🔋 배터리 최적화'),
                const SizedBox(height: 8),
                _batteryCard(),
                const SizedBox(height: 24),

                _sectionTitle('📱 NFC 설정'),
                const SizedBox(height: 8),
                _nfcSettingsCard(),
                const SizedBox(height: 24),

                _sectionTitle('🔊 모닝 브리핑'),
                const SizedBox(height: 8),
                _briefingBgmCard(),
                const SizedBox(height: 24),

                _sectionTitle('🧲 자석 거치대'),
                const SizedBox(height: 8),
                _magnetCard(),
                const SizedBox(height: 24),

                _sectionTitle('ℹ️ 앱 정보'),
                const SizedBox(height: 8),
                _infoCard(),
                const SizedBox(height: 40),
              ]),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: BotanicalTypo.heading(
      size: 16, weight: FontWeight.w700, color: _textSub));
  }

  // ═══ 수면 설정 카드 (6순위: SleepScreen에서 이관) ═══
  Widget _sleepSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 목표 취침 시간
        Row(children: [
          Icon(Icons.nightlight_round, color: const Color(0xFF6B5DAF), size: 20),
          const SizedBox(width: 8),
          Text('목표 취침 시간',
            style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
          const Spacer(),
          GestureDetector(
            onTap: () async {
              final parts = _sleepSettings.targetBedTime.split(':');
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: int.parse(parts[0]),
                  minute: int.parse(parts[1]),
                ),
              );
              if (t != null) {
                final newTime = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                final updated = SleepSettings(
                  targetBedTime: newTime,
                  enabled: _sleepSettings.enabled,
                  appLockEnabled: _sleepSettings.appLockEnabled,
                  screenMonitor: _sleepSettings.screenMonitor,
                  allowedApps: _sleepSettings.allowedApps,
                  warningMinBefore: _sleepSettings.warningMinBefore,
                );
                await _sleepSvc.updateSettings(updated);
                _safeSetState(() => _sleepSettings = updated);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BotanicalDeco.innerInfo(_dk),
              child: Text(_sleepSettings.targetBedTime,
                style: BotanicalTypo.heading(size: 18, color: const Color(0xFF6B5DAF))),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // 취침 알림 토글
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('취침 알림',
              style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text('취침 ${_sleepSettings.warningMinBefore}분 전 경고 + 취침 시간 알림',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
          Switch(
            value: _sleepSettings.enabled,
            onChanged: (v) async {
              final updated = SleepSettings(
                targetBedTime: _sleepSettings.targetBedTime,
                enabled: v,
                appLockEnabled: _sleepSettings.appLockEnabled,
                screenMonitor: _sleepSettings.screenMonitor,
                allowedApps: _sleepSettings.allowedApps,
                warningMinBefore: _sleepSettings.warningMinBefore,
              );
              await _sleepSvc.updateSettings(updated);
              if (mounted) _safeSetState(() => _sleepSettings = updated);
            },
            activeColor: const Color(0xFF6B5DAF),
          ),
        ]),

        if (_sleepSettings.enabled) ...[
          const SizedBox(height: 12),
          // 경고 시점 슬라이더
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('경고 시점',
              style: BotanicalTypo.body(size: 13, weight: FontWeight.w600, color: _textMain)),
            Text('${_sleepSettings.warningMinBefore}분 전',
              style: BotanicalTypo.label(size: 12, weight: FontWeight.w700,
                color: const Color(0xFF6B5DAF))),
          ]),
          Slider(
            value: _sleepSettings.warningMinBefore.toDouble(),
            min: 10, max: 60,
            divisions: 10,
            activeColor: const Color(0xFF6B5DAF),
            onChanged: (v) async {
              final updated = SleepSettings(
                targetBedTime: _sleepSettings.targetBedTime,
                enabled: _sleepSettings.enabled,
                appLockEnabled: _sleepSettings.appLockEnabled,
                screenMonitor: _sleepSettings.screenMonitor,
                allowedApps: _sleepSettings.allowedApps,
                warningMinBefore: v.round(),
              );
              await _sleepSvc.updateSettings(updated);
              if (mounted) _safeSetState(() => _sleepSettings = updated);
            },
          ),
        ],
      ]),
    );
  }

  // ═══ Weather API 카드 ═══
  Widget _weatherApiCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_hasValidKey ? Icons.check_circle : Icons.warning_amber,
            color: _hasValidKey ? BotanicalColors.primary : BotanicalColors.warning,
            size: 20),
          const SizedBox(width: 8),
          Text(
            _hasValidKey ? 'API 키 설정됨' : 'API 키 미설정 (날씨 비활성)',
            style: BotanicalTypo.body(size: 14, weight: FontWeight.w600,
              color: _hasValidKey ? BotanicalColors.primary : BotanicalColors.warning),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _apiKeyController,
          decoration: InputDecoration(
            labelText: 'OpenWeatherMap API Key',
            hintText: '발급받은 API 키를 입력하세요',
            helperText: 'openweathermap.org에서 무료 발급 가능',
            helperStyle: TextStyle(color: _textMuted, fontSize: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: _apiKeyController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: _textMuted, size: 18),
                    onPressed: () {
                      _apiKeyController.clear();
                      _safeSetState(() {});
                    })
                : null,
          ),
          style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: _textMain),
          onChanged: (_) => _safeSetState(() {}),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving || _apiKeyController.text.trim().isEmpty
                ? null
                : _saveApiKey,
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 18),
            label: Text(_saving ? '확인 중...' : '저장 및 테스트'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }

  // ═══ 배터리 최적화 카드 ═══
  Widget _batteryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_batteryExempt ? Icons.battery_full : Icons.battery_alert,
            color: _batteryExempt ? BotanicalColors.primary : BotanicalColors.warning,
            size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(
            _batteryExempt
                ? '배터리 최적화 제외됨 ✅'
                : '배터리 최적화 활성 — 알람 미작동 가능',
            style: BotanicalTypo.body(size: 14, weight: FontWeight.w600,
              color: _batteryExempt ? _textMain : BotanicalColors.warning),
          )),
        ]),
        if (!_batteryExempt) ...[
          const SizedBox(height: 12),
          Text('Samsung 기기에서 배터리 최적화가 켜져 있으면 알람이 정상 작동하지 않을 수 있습니다.',
            style: BotanicalTypo.label(size: 12, color: _textMuted)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _requestBatteryExemption,
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('배터리 최적화 제외 설정'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          )),
        ],
      ]),
    );
  }

  // ═══ NFC 설정 카드 ═══
  Widget _nfcSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(children: [
        Row(children: [
          Icon(Icons.vibration, color: _accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('무진동 NFC 모드 (기본값)',
              style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text('태그 터치 시 시스템 진동/소리 억제',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
          Switch(
            value: _silentNfc,
            onChanged: _nfc.isAvailable ? _toggleSilentNfc : null,
            activeColor: BotanicalColors.gold,
          ),
        ]),
        if (!_nfc.isAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('⚠️ 이 기기는 NFC를 지원하지 않습니다.',
              style: BotanicalTypo.label(size: 11, color: BotanicalColors.error)),
          ),
      ]),
    );
  }

  // ═══ #5b: 브리핑 배경음 카드 ═══
  Widget _briefingBgmCard() {
    const opts = <String, String>{
      'none': '🔇 없음',
      'morning_calm': '🌅 아침의 고요',
      'nature': '🌿 자연의 소리',
      'piano': '🎹 잔잔한 피아노',
      'ambient': '✨ 앰비언트',
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.music_note_rounded, color: _accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('브리핑 배경음',
              style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text('아침 브리핑 시 재생되는 배경음악',
              style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8,
          children: opts.entries.map((e) {
            final sel = _briefingBgm == e.key;
            return GestureDetector(
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('briefing_bgm', e.key);
                _safeSetState(() => _briefingBgm = e.key);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _accent.withOpacity(_dk ? 0.15 : 0.1)
                             : _dk ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? _accent.withOpacity(0.4) : Colors.transparent)),
                child: Text(e.value, style: TextStyle(
                  fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? _accent : _textMain)),
              ),
            );
          }).toList()),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 14, color: _textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text('TTS 종료 시 자동 정지. Native 구현 필요.',
            style: BotanicalTypo.label(size: 10, color: _textMuted))),
        ]),
      ]),
    );
  }

  // ═══ 자석 거치대 설정 ═══
  Widget _magnetCard() {
    final magnet = MagnetService();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 활성화 토글
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('자석 감지 활성화', style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text('거치대 자석으로 집중/휴식 자동 전환', style: BotanicalTypo.label(
              size: 11, color: _textMuted)),
          ])),
          Switch(
            value: _magnetEnabled,
            activeColor: _accent,
            onChanged: (v) {
              magnet.setEnabled(v);
              _safeSetState(() => _magnetEnabled = v);
            },
          ),
        ]),
        if (_magnetEnabled) ...[
          const SizedBox(height: 16),
          // 현재 자기장 / 임계값 표시
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('현재 자기장', style: TextStyle(fontSize: 10, color: _textMuted)),
                const SizedBox(height: 2),
                Text('${magnet.lastMagnitude.toStringAsFixed(1)} uT',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                    color: magnet.isOnCradle ? const Color(0xFF10B981) : _textMain,
                    fontFamily: 'monospace')),
              ])),
              Container(width: 1, height: 30, color: _textMuted.withOpacity(0.2)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('임계값', style: TextStyle(fontSize: 10, color: _textMuted)),
                const SizedBox(height: 2),
                Text('${magnet.threshold.toStringAsFixed(1)} uT',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                    color: _accent, fontFamily: 'monospace')),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          // 상태 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: magnet.isOnCradle
                ? const Color(0xFF10B981).withOpacity(0.1)
                : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: magnet.isOnCradle ? const Color(0xFF10B981) : Colors.orange)),
              const SizedBox(width: 8),
              Text(magnet.isOnCradle ? '거치대 감지됨' : '거치대 미감지',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: magnet.isOnCradle ? const Color(0xFF10B981) : Colors.orange)),
            ]),
          ),
          const SizedBox(height: 12),
          // 캘리브레이션 버튼
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _calibrateMagnet,
              icon: Icon(Icons.tune_rounded, size: 16, color: _accent),
              label: Text('캘리브레이션', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _accent)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: _accent.withOpacity(0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ]),
    );
  }

  void _calibrateMagnet() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool measuring = false;
        double? result;
        return StatefulBuilder(builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('자석 캘리브레이션',
              style: BotanicalTypo.heading(size: 16, color: _textMain)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (result != null) ...[
                Icon(Icons.check_circle_rounded, size: 48, color: const Color(0xFF10B981)),
                const SizedBox(height: 12),
                Text('완료!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textMain)),
                const SizedBox(height: 4),
                Text('임계값: ${result!.toStringAsFixed(1)} uT',
                  style: TextStyle(fontSize: 14, color: _accent, fontFamily: 'monospace')),
              ] else if (measuring) ...[
                const SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: 12),
                Text('측정 중... (3초)', style: TextStyle(fontSize: 14, color: _textSub)),
              ] else ...[
                Icon(Icons.phone_android_rounded, size: 48, color: _textMuted),
                const SizedBox(height: 12),
                Text('폰을 거치대에 올려놓은 상태에서\n측정을 시작하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: _textSub, height: 1.5)),
              ],
            ]),
            actions: [
              if (result != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _safeSetState(() {});
                  },
                  child: Text('확인', style: TextStyle(color: _accent, fontWeight: FontWeight.w700)))
              else if (!measuring) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('취소', style: TextStyle(color: _textMuted))),
                TextButton(
                  onPressed: () async {
                    setDlg(() => measuring = true);
                    final t = await MagnetService().calibrate();
                    setDlg(() { measuring = false; result = t; });
                  },
                  child: Text('측정 시작', style: TextStyle(color: _accent, fontWeight: FontWeight.w700))),
              ],
            ],
          );
        });
      },
    );
  }

  // ═══ 앱 정보 카드 ═══
  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _infoRow('버전', 'v8.7'),
        const SizedBox(height: 8),
        _infoRow('Firebase UID', 'sJ8Pxusw9gR0tNR44RhkIge7OiG2'),
        const SizedBox(height: 8),
        _infoRow('시험일', '2026-03-07 (5급 PSAT)'),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(children: [
      Text(label, style: BotanicalTypo.label(size: 12, weight: FontWeight.w600, color: _textMuted)),
      const SizedBox(width: 12),
      Expanded(child: Text(value,
        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: _textSub),
        textAlign: TextAlign.end)),
    ]);
  }
}