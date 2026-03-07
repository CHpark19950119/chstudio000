import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';

class QrSetupScreen extends StatefulWidget {
  final AlarmSettings settings;
  const QrSetupScreen({super.key, required this.settings});
  @override
  State<QrSetupScreen> createState() => _QrSetupScreenState();
}

class _QrSetupScreenState extends State<QrSetupScreen> {
  late String _secret;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  @override
  void initState() { super.initState(); _secret = widget.settings.qrSecret; }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('QR 기상 인증 설정', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        // 안내 카드
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [BotanicalColors.primary, BotanicalColors.primaryLight],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: BotanicalColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text('QR 코드 기상 인증',
                style: BotanicalTypo.heading(size: 18, color: Colors.white))),
            ]),
            const SizedBox(height: 16),
            Text('아래 QR 코드를 스크린샷으로 저장하거나\n인쇄하여 욕실에 부착하세요.\n\n알람이 울리면 이 QR을 스캔해야만\n기상이 인정됩니다.',
              style: BotanicalTypo.body(size: 13, color: Colors.white.withOpacity(0.9)).copyWith(height: 1.6)),
          ]),
        ),
        const SizedBox(height: 32),

        // QR 코드 카드
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Column(children: [
            QrImageView(
              data: _secret, version: QrVersions.auto, size: 220,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: BotanicalColors.textMain),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: BotanicalColors.textMain),
              gapless: true,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: BotanicalColors.surfaceLight,
                borderRadius: BorderRadius.circular(12)),
              child: Text('CHEONHONG STUDIO', style: BotanicalTypo.brand()),
            ),
            const SizedBox(height: 8),
            Text('🚿 욕실에 부착하세요', style: BotanicalTypo.label(size: 13, color: BotanicalColors.textMuted)),
          ]),
        ),
        const SizedBox(height: 24),

        _stepCard('1', '이 화면을 스크린샷 찍기', '또는 프린트하여 욕실 벽에 부착', Icons.screenshot_rounded),
        const SizedBox(height: 12),
        _stepCard('2', '알람이 울리면 앱 열기', '알림을 탭하면 QR 스캐너가 열립니다', Icons.alarm_rounded),
        const SizedBox(height: 12),
        _stepCard('3', '욕실에서 QR 스캔', '스캔 완료 시 기상시간이 자동 기록됩니다', Icons.qr_code_scanner_rounded),
        const SizedBox(height: 32),

        OutlinedButton.icon(
          onPressed: () {
            _safeSetState(() { _secret = 'CHEONHONG_WAKE_${DateTime.now().millisecondsSinceEpoch}'; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('새 QR 코드가 생성되었습니다. 다시 인쇄하세요.')));
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text('새 QR 코드 생성', style: BotanicalTypo.body(size: 14, weight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _textMuted,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(color: _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight)),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _stepCard(String num, String title, String sub, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight)),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(num, style: BotanicalTypo.heading(
            size: 16, weight: FontWeight.w800, color: _accent)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: _textMain)),
          Text(sub, style: BotanicalTypo.label(size: 11, color: _textMuted)),
        ])),
        Icon(icon, size: 20, color: _textMuted),
      ]),
    );
  }
}
