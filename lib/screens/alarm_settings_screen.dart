import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/alarm_service.dart';
import '../services/firebase_service.dart';
import 'qr_setup_screen.dart';

class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});
  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  AlarmSettings _settings = AlarmSettings();
  bool _loading = true;
  bool _batteryOptExempt = false;
  bool _canExactAlarm = true;
  String _bgmType = 'piano';

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.gold;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    try {
      _settings = await FirebaseService().getAlarmSettings();
    } catch (_) {}
    _batteryOptExempt = await AlarmService.isBatteryOptExempt();
    _canExactAlarm = await AlarmService.canScheduleExactAlarms();
    try {
      final sp = await SharedPreferences.getInstance();
      _bgmType = sp.getString('alarm_bgm_type') ?? 'piano';
    } catch (_) {}
    _safeSetState(() => _loading = false);
  }

  Future<void> _save() async {
    _safeSetState(() => _loading = true);
    try {
      await AlarmService().scheduleAlarm(_settings);
      // BGM 타입 저장 (네이티브 + Flutter)
      await AlarmService.cacheBgmType(_bgmType);
      final sp = await SharedPreferences.getInstance();
      await sp.setString('alarm_bgm_type', _bgmType);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 알람 설정 저장됨')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 저장 실패: $e')));
      }
    }
    _safeSetState(() => _loading = false);
  }

  AlarmSettings _copyWith({
    String? targetWakeTime, bool? enabled, List<int>? activeDays,
    int? snoozeMinutes, bool? qrWakeEnabled, bool? nfcWakeEnabled,
  }) => AlarmSettings(
    targetWakeTime: targetWakeTime ?? _settings.targetWakeTime,
    enabled: enabled ?? _settings.enabled,
    activeDays: activeDays ?? _settings.activeDays,
    snoozeMinutes: snoozeMinutes ?? _settings.snoozeMinutes,
    ringtone: _settings.ringtone,
    vibrate: _settings.vibrate,
    qrWakeEnabled: qrWakeEnabled ?? _settings.qrWakeEnabled,
    qrSecret: _settings.qrSecret,
    nfcWakeEnabled: nfcWakeEnabled ?? _settings.nfcWakeEnabled,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('기상 알람 설정', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: _accent))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!_batteryOptExempt || !_canExactAlarm) _systemWarningCard(),
              if (!_batteryOptExempt || !_canExactAlarm) const SizedBox(height: 16),
              _enableToggle(),
              const SizedBox(height: 16),
              _timePicker(),
              const SizedBox(height: 16),
              _daySelector(),
              const SizedBox(height: 16),
              _snoozeSlider(),
              const SizedBox(height: 16),
              _qrToggle(),
              const SizedBox(height: 16),
              _nfcWakeToggle(),
              const SizedBox(height: 16),
              _bgmSelector(),
              const SizedBox(height: 32),
              _saveButton(),
            ],
          ),
    );
  }

  Widget _systemWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.warning.withOpacity(0.1) : const Color(0xFFFDF8EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BotanicalColors.warning.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('알람 안정성 설정 필요', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: BotanicalColors.warning)),
        ]),
        const SizedBox(height: 8),
        if (!_batteryOptExempt) ...[
          Text('Samsung 기기는 배터리 최적화로 알람이 울리지 않을 수 있습니다.',
            style: BotanicalTypo.label(size: 12, color: BotanicalColors.warning)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () async {
              await AlarmService.requestBatteryOptExemption();
              await Future.delayed(const Duration(seconds: 1));
              _batteryOptExempt = await AlarmService.isBatteryOptExempt();
              _safeSetState(() {});
            },
            icon: const Icon(Icons.battery_saver, size: 16),
            label: Text('배터리 최적화 제외 설정', style: BotanicalTypo.label(size: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: BotanicalColors.warning,
              side: const BorderSide(color: BotanicalColors.warning)),
          )),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => AlarmService.openBatterySettings(),
            child: Text('  Samsung: 설정 > 배터리 > 앱 절전 > 이 앱 제외',
              style: BotanicalTypo.label(size: 10, color: BotanicalColors.warning)
                .copyWith(decoration: TextDecoration.underline)),
          ),
        ],
        if (!_canExactAlarm) ...[
          const SizedBox(height: 8),
          Text('정확한 알람 권한이 필요합니다.',
            style: BotanicalTypo.label(size: 12, color: BotanicalColors.warning)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () async {
              await AlarmService.requestExactAlarmPermission();
              await Future.delayed(const Duration(seconds: 1));
              _canExactAlarm = await AlarmService.canScheduleExactAlarms();
              _safeSetState(() {});
            },
            icon: const Icon(Icons.alarm, size: 16),
            label: Text('정확한 알람 허용', style: BotanicalTypo.label(size: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: BotanicalColors.warning,
              side: const BorderSide(color: BotanicalColors.warning)),
          )),
        ],
      ]),
    );
  }

  Widget _enableToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BotanicalDeco.card(_dk),
      child: SwitchListTile(
        title: Text('알람 활성화', style: BotanicalTypo.heading(size: 16, color: _textMain)),
        subtitle: Text(_settings.enabled ? '매일 알람이 울립니다' : '알람이 꺼져 있습니다',
          style: BotanicalTypo.label(size: 12, color: _textMuted)),
        value: _settings.enabled,
        onChanged: (v) => _safeSetState(() => _settings = _copyWith(enabled: v)),
        activeColor: _accent,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _timePicker() {
    final parts = _settings.targetWakeTime.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context, initialTime: TimeOfDay(hour: h, minute: m));
        if (picked != null) {
          final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          _safeSetState(() => _settings = _copyWith(targetWakeTime: t));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BotanicalDeco.card(_dk),
        child: Center(
          child: Text(_settings.targetWakeTime,
            style: BotanicalTypo.number(size: 48, weight: FontWeight.w300, color: _accent)),
        ),
      ),
    );
  }

  Widget _daySelector() {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('활성 요일', style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (i) {
            final dayNum = i + 1;
            final active = _settings.activeDays.contains(dayNum);
            return GestureDetector(
              onTap: () {
                final newDays = List<int>.from(_settings.activeDays);
                active ? newDays.remove(dayNum) : newDays.add(dayNum);
                _safeSetState(() => _settings = _copyWith(activeDays: newDays));
              },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: active ? _accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: active ? _accent : (_dk ? BotanicalColors.borderDark : BotanicalColors.borderLight)),
                ),
                child: Center(child: Text(days[i], style: BotanicalTypo.label(
                  size: 12, weight: FontWeight.w600,
                  color: active ? Colors.white : _textMuted))),
              ),
            );
          })),
      ]),
    );
  }

  Widget _snoozeSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('스누즈', style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
          Text('${_settings.snoozeMinutes}분', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _accent)),
        ]),
        Slider(
          value: _settings.snoozeMinutes.toDouble(),
          min: 1, max: 15, divisions: 14,
          activeColor: _accent,
          onChanged: (v) => _safeSetState(() => _settings = _copyWith(snoozeMinutes: v.round())),
        ),
      ]),
    );
  }

  Widget _qrToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BotanicalDeco.card(_dk),
      child: Column(children: [
        SwitchListTile(
          title: Text('🚿 QR 기상 인증', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w600, color: _textMain)),
          subtitle: Text('욕실 QR 스캔 후 기상 확정', style: BotanicalTypo.label(
            size: 11, color: _textMuted)),
          value: _settings.qrWakeEnabled,
          onChanged: (v) => _safeSetState(() => _settings = _copyWith(qrWakeEnabled: v)),
          activeColor: BotanicalColors.subjectVerbal,
          contentPadding: EdgeInsets.zero,
        ),
        if (_settings.qrWakeEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => QrSetupScreen(settings: _settings))),
              icon: const Icon(Icons.qr_code, size: 16),
              label: Text('QR 코드 설정', style: BotanicalTypo.label(size: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: BotanicalColors.subjectVerbal,
                side: const BorderSide(color: BotanicalColors.subjectVerbal)),
            )),
          ),
      ]),
    );
  }

  Widget _nfcWakeToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BotanicalDeco.card(_dk),
      child: SwitchListTile(
        title: Text('📱 NFC 기상 해제', style: BotanicalTypo.body(
          size: 14, weight: FontWeight.w600, color: _textMain)),
        subtitle: Text('욕실 NFC 태그 스캔 시 알람 해제 + 기상시간 기록',
          style: BotanicalTypo.label(size: 11, color: _textMuted)),
        value: _settings.nfcWakeEnabled,
        onChanged: (v) => _safeSetState(() => _settings = _copyWith(nfcWakeEnabled: v)),
        activeColor: BotanicalColors.subjectConst,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _bgmSelector() {
    const options = [
      ('piano', '🎹 피아노', '잔잔한 피아노 앰비언트'),
      ('nature', '🌿 자연소리', '부드러운 바람소리'),
      ('rain', '🌧️ 빗소리', '차분한 빗소리'),
      ('none', '🔇 없음', '배경음 없이 TTS만'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _dk ? Colors.white10 : const Color(0xFFF0EDE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎵 기상 배경음', style: BotanicalTypo.heading(
            size: 14, weight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 4),
          Text('알람 시 재생될 배경음악 (볼륨 30%)', style: BotanicalTypo.label(
            size: 11, color: _textMuted)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final selected = _bgmType == o.$1;
              return GestureDetector(
                onTap: () => _safeSetState(() => _bgmType = o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                      ? _accent.withOpacity(0.15)
                      : (_dk ? Colors.white10 : const Color(0xFFF8F6F2)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? _accent : Colors.transparent,
                      width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(o.$2, style: BotanicalTypo.label(
                        size: 13, weight: FontWeight.w700,
                        color: selected ? _accent : _textSub)),
                      const SizedBox(height: 2),
                      Text(o.$3, style: BotanicalTypo.label(
                        size: 9, color: _textMuted)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _dk ? BotanicalColors.scaffoldDark : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: Text('저장', style: BotanicalTypo.heading(size: 16,
          color: _dk ? BotanicalColors.scaffoldDark : Colors.white)),
      ),
    );
  }
}