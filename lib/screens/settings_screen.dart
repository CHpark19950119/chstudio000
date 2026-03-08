import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/botanical_theme.dart';
import '../services/weather_service.dart';
import '../services/nfc_service.dart';
import '../services/cradle_service.dart';

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
  final _apiKeyController = TextEditingController();

  bool _loading = true;
  bool _hasValidKey = false;
  bool _silentNfc = false;
  bool _saving = false;
  bool _cradleEnabled = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

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

    if (key != null && key.isNotEmpty && key != 'YOUR_OPENWEATHERMAP_API_KEY') {
      _apiKeyController.text = key;
    }

    _cradleEnabled = CradleService().isEnabled;

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

                _sectionTitle('📱 NFC 설정'),
                const SizedBox(height: 8),
                _nfcSettingsCard(),
                const SizedBox(height: 24),

                _sectionTitle('📱 거치대 감지'),
                const SizedBox(height: 8),
                _cradleCard(),
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

  // ═══ 거치대 감지 설정 ═══
  Widget _cradleCard() {
    final cradle = CradleService();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('거치대 감지 활성화', style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text('캘리브레이션 각도 기준 거치대 감지', style: BotanicalTypo.label(
              size: 11, color: _textMuted)),
          ])),
          Switch(
            value: _cradleEnabled,
            activeColor: _accent,
            onChanged: (v) {
              cradle.setEnabled(v);
              _safeSetState(() => _cradleEnabled = v);
            },
          ),
        ]),
        if (_cradleEnabled) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cradle.isOnCradle
                  ? const Color(0xFF10B981).withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: cradle.isOnCradle ? const Color(0xFF10B981) : Colors.orange)),
              const SizedBox(width: 8),
              Text(cradle.isOnCradle ? '거치대 감지됨' : '거치대 미감지',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: cradle.isOnCradle ? const Color(0xFF10B981) : Colors.orange)),
              const Spacer(),
              if (cradle.isCalibrated)
                Text('캘리브레이션 완료', style: TextStyle(
                  fontSize: 10, color: _textMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _calibrateCradle,
              icon: Icon(Icons.tune_rounded, size: 16, color: _accent),
              label: Text(cradle.isCalibrated ? '재캘리브레이션' : '캘리브레이션',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accent)),
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

  void _calibrateCradle() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool measuring = false;
        bool done = false;
        return StatefulBuilder(builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('거치대 캘리브레이션',
              style: BotanicalTypo.heading(size: 16, color: _textMain)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (done) ...[
                Icon(Icons.check_circle_rounded, size: 48, color: const Color(0xFF10B981)),
                const SizedBox(height: 12),
                Text('완료!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textMain)),
                const SizedBox(height: 4),
                Text('거치대 기준값 저장됨', style: TextStyle(fontSize: 14, color: _accent)),
              ] else if (measuring) ...[
                const SizedBox(width: 48, height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: 12),
                Text('측정 중... (5초)', style: TextStyle(fontSize: 14, color: _textSub)),
              ] else ...[
                Icon(Icons.phone_android_rounded, size: 48, color: _textMuted),
                const SizedBox(height: 12),
                Text('폰을 거치대에 올려놓고\n측정을 시작하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: _textSub, height: 1.5)),
              ],
            ]),
            actions: [
              if (done)
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
                    await CradleService().calibrate();
                    setDlg(() { measuring = false; done = true; });
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
        _infoRow('버전', 'v9.5'),
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