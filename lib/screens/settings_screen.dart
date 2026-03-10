import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hive/hive.dart';
import '../theme/botanical_theme.dart';
import '../services/nfc_service.dart';
import '../services/local_cache_service.dart';
import 'nfc/nfc_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nfc = NfcService();
  bool _loading = true;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else { setState(fn); }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _nfc.initialize();
    _safeSetState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('관리', style: BotanicalTypo.heading(size: 18, color: _textMain)),
        backgroundColor: Colors.transparent, elevation: 0,
        foregroundColor: _textMain,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ─── NFC & 자동화 진입 ───
              _nfcEntryCard(),
              const SizedBox(height: 16),

              // ─── 앱 정보 ───
              _infoCard(),
              const SizedBox(height: 16),

              // ─── 데이터 관리 ───
              _dataManagementCard(),
              const SizedBox(height: 40),
            ]),
          ),
    );
  }

  // ═══ NFC & 자동화 진입 카드 ═══
  Widget _nfcEntryCard() {
    final tagCount = _nfc.tags.length;
    return GestureDetector(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NfcScreen())),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BotanicalDeco.card(_dk),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _accent.withOpacity(_dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.nfc_rounded, size: 24, color: _accent),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('자동화', style: BotanicalTypo.body(
              size: 15, weight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text('NFC 태그, 거치대 감지, 자동 루틴', style: BotanicalTypo.label(
              size: 11, color: _textMuted)),
          ])),
          if (tagCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
              child: Text('$tagCount', style: BotanicalTypo.label(
                size: 12, weight: FontWeight.w800, color: _accent)),
            ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: _textMuted, size: 22),
        ]),
      ),
    );
  }

  // ═══ 앱 정보 카드 ═══
  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _textMuted),
          const SizedBox(width: 8),
          Text('앱 정보', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
        ]),
        const SizedBox(height: 14),
        _infoRow('버전', 'v10.2'),
        const SizedBox(height: 8),
        _infoRow('Firebase UID', 'sJ8Pxusw9gR0tNR44RhkIge7OiG2'),
        const SizedBox(height: 8),
        _infoRow('시험일', '2026-03-07 (5급 PSAT)'),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(children: [
      Text(label, style: BotanicalTypo.label(
        size: 12, weight: FontWeight.w600, color: _textMuted)),
      const SizedBox(width: 12),
      Expanded(child: Text(value,
        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: _textSub),
        textAlign: TextAlign.end)),
    ]);
  }

  // ═══ 데이터 관리 카드 ═══
  Widget _dataManagementCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.storage_rounded, size: 18, color: _textMuted),
          const SizedBox(width: 8),
          Text('데이터 관리', style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
        ]),
        const SizedBox(height: 14),

        // Hive 캐시 초기화
        _dangerAction(
          icon: Icons.cached_rounded,
          label: '로컬 캐시 초기화',
          desc: 'Hive 캐시 삭제 (Firestore에서 재동기화)',
          onTap: () => _confirmClear(
            title: '로컬 캐시 초기화',
            message: '모든 로컬 캐시가 삭제됩니다.\nFirestore에서 데이터를 다시 불러옵니다.\n\n계속하시겠습니까?',
            onConfirm: () async {
              try {
                await Hive.deleteBoxFromDisk('chstudio_cache');
                await LocalCacheService().init();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('캐시 초기화 완료. 앱을 재시작하세요.'),
                    backgroundColor: BotanicalColors.success));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('오류: $e'),
                    backgroundColor: BotanicalColors.error));
                }
              }
            },
          ),
        ),
      ]),
    );
  }

  Widget _dangerAction({
    required IconData icon, required String label,
    required String desc, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BotanicalColors.error.withOpacity(_dk ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BotanicalColors.error.withOpacity(0.12))),
        child: Row(children: [
          Icon(icon, size: 20, color: BotanicalColors.error.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: BotanicalTypo.body(
              size: 13, weight: FontWeight.w600, color: _textMain)),
            const SizedBox(height: 2),
            Text(desc, style: BotanicalTypo.label(size: 10, color: _textMuted)),
          ])),
          Icon(Icons.chevron_right_rounded, color: _textMuted, size: 18),
        ]),
      ),
    );
  }

  void _confirmClear({
    required String title, required String message,
    required VoidCallback onConfirm,
  }) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: BotanicalColors.error, size: 22),
        const SizedBox(width: 8),
        Text(title, style: BotanicalTypo.heading(size: 16, color: _textMain)),
      ]),
      content: Text(message, style: BotanicalTypo.body(
        size: 13, color: _textSub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('취소', style: TextStyle(color: _textMuted))),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); onConfirm(); },
          style: ElevatedButton.styleFrom(
            backgroundColor: BotanicalColors.error,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('초기화', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      ],
    ));
  }
}
