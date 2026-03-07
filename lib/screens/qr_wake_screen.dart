import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';

class QrWakeScreen extends StatefulWidget {
  final AlarmSettings settings;
  const QrWakeScreen({super.key, required this.settings});
  @override
  State<QrWakeScreen> createState() => _QrWakeScreenState();
}

class _QrWakeScreenState extends State<QrWakeScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _verified = false;
  bool _processing = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _scanner.dispose(); _pulseCtrl.dispose(); super.dispose(); }

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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _verified) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      if (value == widget.settings.qrSecret || value.startsWith('CHEONHONG_WAKE')) {
        _processing = true;
        await _recordWakeTime();
        _safeSetState(() => _verified = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
        return;
      }
    }
  }

  Future<void> _recordWakeTime() async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm').format(now);
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];
      await fb.updateTimeRecord(dateStr,
        TimeRecord(date: dateStr, wake: timeStr, study: existing?.study));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BotanicalColors.scaffoldDark,
      body: SafeArea(child: _verified ? _successView() : _scannerView()),
    );
  }

  Widget _scannerView() {
    return Stack(children: [
      MobileScanner(controller: _scanner, onDetect: _onDetect),
      // 상단 오버레이
      Positioned(top: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [BotanicalColors.scaffoldDark, BotanicalColors.scaffoldDark.withOpacity(0)],
          )),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context, false)),
            Text('QR 기상 인증', style: BotanicalTypo.heading(size: 18, color: BotanicalColors.textMainDark)),
            const SizedBox(width: 48),
          ]),
        ),
      ),
      // 스캔 프레임
      Center(child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (ctx, child) => Transform.scale(
          scale: _pulseAnim.value,
          child: Container(width: 260, height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: BotanicalColors.primary.withOpacity(0.8), width: 3),
              boxShadow: [BoxShadow(
                color: BotanicalColors.primary.withOpacity(0.2), blurRadius: 30, spreadRadius: 5)],
            ),
          ),
        ),
      )),
      // 하단 안내
      Positioned(bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
          decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [BotanicalColors.scaffoldDark, BotanicalColors.scaffoldDark.withOpacity(0)],
          )),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.qr_code_rounded, color: Colors.white70, size: 20),
                const SizedBox(width: 10),
                Text('욕실의 QR 코드를 스캔하세요',
                  style: BotanicalTypo.body(size: 14, weight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
            const SizedBox(height: 12),
            Text('알람 시간: ${widget.settings.targetWakeTime}  ·  현재: ${DateFormat('HH:mm').format(DateTime.now())}',
              style: BotanicalTypo.label(size: 12, color: BotanicalColors.textMutedDark)),
          ]),
        ),
      ),
    ]);
  }

  Widget _successView() {
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [BotanicalColors.scaffoldDark, BotanicalColors.cardDark],
      )),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [BotanicalColors.subjectData, BotanicalColors.primaryLight]),
            boxShadow: [BoxShadow(
              color: BotanicalColors.subjectData.withOpacity(0.4), blurRadius: 40, spreadRadius: 10)],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 56)),
        const SizedBox(height: 32),
        Text('기상 인증 완료 ☀️', style: BotanicalTypo.heading(
          size: 24, weight: FontWeight.w800, color: BotanicalColors.textMainDark)),
        const SizedBox(height: 12),
        Text(timeStr, style: BotanicalTypo.number(
          size: 56, color: BotanicalColors.subjectData)),
        const SizedBox(height: 8),
        Text('기상시간이 기록되었습니다',
          style: BotanicalTypo.label(size: 14, color: BotanicalColors.textMutedDark)),
      ]),
    );
  }
}
