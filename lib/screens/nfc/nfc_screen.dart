import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/nfc_service.dart';
import '../../services/cradle_service.dart';
import '../../services/geofence_service.dart';

class NfcScreen extends StatefulWidget {
  const NfcScreen({super.key});
  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> with TickerProviderStateMixin {
  final _nfc = NfcService();

  bool _isScanning = false;
  bool _registering = false;
  bool _isWritingNdef = false;
  bool _nfcLoading = true;
  String? _lastScannedUid;
  NfcTagConfig? _lastMatchedTag;
  String _statusMessage = '';
  NfcTagRole _selectedRole = NfcTagRole.wake;
  final _nameCtrl = TextEditingController();

  late AnimationController _pulseCtrl;
  bool _cradleEnabled = false;
  bool _silentNfc = false;
  bool _geoEnabled = false;
  bool _geoSettingHome = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _main => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _sub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _muted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _ac => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;
  Color get _card => _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight;
  Color get _bdr => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;

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
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    await _nfc.initialize();
    _silentNfc = _nfc.isSilentReaderEnabled;
    _cradleEnabled = CradleService().isEnabled;
    _geoEnabled = GeofenceService().enabled;
    if (mounted) setState(() => _nfcLoading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pulseCtrl.dispose();
    _nfc.stopScan();
    super.dispose();
  }

  // ── Actions ──
  void _startScan({bool forRegister = false}) {
    if (!_nfc.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('NFC 미지원 기기'), backgroundColor: BotanicalColors.error));
      return;
    }
    setState(() {
      _isScanning = true; _registering = forRegister;
      _lastScannedUid = null; _lastMatchedTag = null;
      _statusMessage = '태그를 가까이 대주세요…';
    });
    _nfc.startScan(
      executeOnMatch: !forRegister,
      onDetected: (matched, uid) {
        if (!mounted) return;
        setState(() {
          _isScanning = false; _lastScannedUid = uid; _lastMatchedTag = matched;
          if (_registering) {
            _statusMessage = matched != null
              ? '이미 등록: ${matched.name}' : '새 태그 감지됨';
            if (matched != null) _registering = false;
          } else {
            _statusMessage = matched != null
              ? '${matched.emoji} ${matched.roleLabel} 완료!' : '미등록 태그';
          }
        });
      },
      onError: (e) { if (mounted) setState(() { _isScanning = false; _statusMessage = e; }); },
    );
  }

  Future<void> _registerTag() async {
    if (_lastScannedUid == null || _nameCtrl.text.trim().isEmpty) return;
    final tag = await _nfc.registerTag(
      name: _nameCtrl.text.trim(), role: _selectedRole, nfcUid: _lastScannedUid!);
    if (!mounted) return;
    setState(() { _registering = false; _lastScannedUid = null; _nameCtrl.clear();
      _statusMessage = '등록 완료!'; });
    _showNdefDialog(tag);
  }

  void _showNdefDialog(NfcTagConfig tag) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('NDEF 쓰기'),
      content: Text('${tag.emoji} ${tag.roleLabel} 자동실행을 쓰시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('건너뛰기')),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); _writeNdef(tag); },
          child: const Text('쓰기')),
      ],
    ));
  }

  Future<void> _writeNdef(NfcTagConfig tag) async {
    setState(() { _isWritingNdef = true; _statusMessage = '태그를 대세요…'; });
    final ok = await _nfc.writeNdefToTag(
      role: tag.role, tagId: tag.id,
      onStatus: (s) { if (mounted) setState(() => _statusMessage = s); });
    if (!mounted) return;
    setState(() { _isWritingNdef = false; _statusMessage = ok ? 'NDEF 완료!' : 'NDEF 실패'; });
  }

  Future<void> _deleteTag(NfcTagConfig tag) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('${tag.emoji} ${tag.name} 삭제?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제', style: TextStyle(color: BotanicalColors.error))),
      ],
    ));
    if (ok == true) await _nfc.removeTag(tag.id);
  }

  Future<void> _testRole(NfcTagRole role) async {
    final r = await _nfc.manualTestRole(role);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r), behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  Color _rc(NfcTagRole r) {
    switch (r) {
      case NfcTagRole.wake: return BotanicalColors.gold;
      case NfcTagRole.outing: return const Color(0xFF3B8A6B);
      case NfcTagRole.study: return BotanicalColors.primary;
      case NfcTagRole.sleep: return const Color(0xFF5C6BC0);
      case NfcTagRole.meal: return const Color(0xFFFF8A65);
    }
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dk ? BotanicalColors.scaffoldDark : BotanicalColors.scaffoldLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        foregroundColor: _main,
        title: Text('자동화', style: BotanicalTypo.heading(size: 18, color: _main)),
        actions: [
          if (_nfc.isAvailable)
            Padding(padding: const EdgeInsets.only(right: 14),
              child: _pill('NFC', BotanicalColors.success)),
        ],
      ),
      body: _nfcLoading
        ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: _ac))
        : ListenableBuilder(listenable: _nfc, builder: (_, __) => _body()),
    );
  }

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 5, height: 5,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
    ]));

  Widget _body() {
    final tags = _nfc.tags;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
      // ── 상태 ──
      _statusBar(),
      const SizedBox(height: 14),

      // ── 태그 목록 ──
      _label('태그  ${tags.length}'),
      const SizedBox(height: 8),
      if (tags.isEmpty) _empty()
      else ...tags.map(_tagRow),
      const SizedBox(height: 14),

      // ── 스캔 ──
      _scanRow(),
      if (_registering && _lastScannedUid != null && _lastMatchedTag == null) ...[
        const SizedBox(height: 10),
        _regForm(),
      ],
      const SizedBox(height: 18),

      // ── 설정 ──
      _label('설정'),
      const SizedBox(height: 8),
      _settingsCard(),
      const SizedBox(height: 14),

      // ── 수동 테스트 ──
      _testTile(),
      const SizedBox(height: 14),

      // ── 역할 요약 ──
      _roleSummary(),
    ]);
  }

  // ══════════ 상태 바 ══════════
  Widget _statusBar() {
    return Row(children: [
      _sPill('🚪', _nfc.isOut ? '외출' : '집', _nfc.isOut, const Color(0xFF3B8A6B)),
      const SizedBox(width: 8),
      _sPill('📚', _nfc.isStudying ? '공부중' : '대기', _nfc.isStudying, BotanicalColors.subjectVerbal),
      const SizedBox(width: 8),
      _sPill('🍽️', _nfc.isMealing ? '식사중' : '대기', _nfc.isMealing, const Color(0xFFFF8A65)),
    ]);
  }

  Widget _sPill(String emoji, String label, bool on, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: on ? c.withOpacity(0.06) : _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? c.withOpacity(0.25) : _bdr)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: on ? c : _muted)),
        if (on) ...[
          const SizedBox(width: 5),
          Container(width: 5, height: 5,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        ],
      ]),
    ),
  );

  // ══════════ 라벨 ══════════
  Widget _label(String t) => Text(t, style: BotanicalTypo.label(
    size: 10, weight: FontWeight.w700, letterSpacing: 1.2, color: _muted));

  // ══════════ 태그 행 ══════════
  Widget _tagRow(NfcTagConfig tag) {
    final c = _rc(tag.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bdr)),
      child: Row(children: [
        Container(width: 32, height: 32,
          decoration: BoxDecoration(
            color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(tag.emoji, style: const TextStyle(fontSize: 16)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tag.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _main)),
          Text(tag.roleLabel, style: TextStyle(fontSize: 10, color: _muted)),
        ])),
        _miniBtn(Icons.play_arrow_rounded, () => _testRole(tag.role)),
        const SizedBox(width: 4),
        _miniBtn(Icons.edit_note_rounded, () => _writeNdef(tag)),
        const SizedBox(width: 4),
        _miniBtn(Icons.close_rounded, () => _deleteTag(tag),
          color: BotanicalColors.error.withOpacity(0.6)),
      ]),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap, {Color? color}) => GestureDetector(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 18, color: color ?? _muted)));

  // ══════════ 스캔 행 ══════════
  Widget _scanRow() {
    final busy = _isScanning || _isWritingNdef;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _ac.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _ac.withOpacity(0.12))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_statusMessage.isNotEmpty) ...[
          Text(_statusMessage, style: TextStyle(fontSize: 12, color: _sub),
            textAlign: TextAlign.center),
          const SizedBox(height: 10),
        ],
        Row(children: [
          Expanded(child: _actBtn(
            busy ? '스캔 중…' : '태그 스캔', Icons.sensors_rounded, true,
            busy ? null : () => _startScan())),
          const SizedBox(width: 8),
          Expanded(child: _actBtn(
            '새 태그 등록', Icons.add_rounded, false,
            busy ? null : () => _startScan(forRegister: true))),
        ]),
      ]),
    );
  }

  Widget _actBtn(String label, IconData icon, bool filled, VoidCallback? onTap) =>
    GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: filled ? _ac : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: filled ? null : Border.all(color: _ac.withOpacity(0.3))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: filled ? Colors.white : _ac),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: filled ? Colors.white : _ac)),
      ]),
    ));

  // ══════════ 등록 폼 ══════════
  Widget _regForm() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _card, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _ac.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('UID: $_lastScannedUid',
        style: TextStyle(fontSize: 10, color: _muted, fontFamily: 'monospace')),
      const SizedBox(height: 10),
      TextField(controller: _nameCtrl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: '태그 이름', hintText: '욕실, 책상, 현관',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onChanged: (_) => setState(() {})),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6,
        children: NfcTagRole.values.map((r) {
          final sel = _selectedRole == r;
          final tag = NfcTagConfig(id: '', name: '', role: r, createdAt: '');
          return GestureDetector(
            onTap: () => setState(() => _selectedRole = r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? _ac.withOpacity(0.08) : _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? _ac.withOpacity(0.4) : _bdr)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tag.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(tag.roleLabel.split(' ').first, style: TextStyle(
                  fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? _ac : _sub)),
              ]),
            ),
          );
        }).toList()),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: GestureDetector(
        onTap: _nameCtrl.text.trim().isNotEmpty ? _registerTag : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _nameCtrl.text.trim().isNotEmpty ? _ac : _ac.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10)),
          child: const Center(child: Text('등록', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
        ),
      )),
    ]),
  );

  // ══════════ 설정 카드 (거치대 + 무진동 합침) ══════════
  Widget _settingsCard() {
    final cradle = CradleService();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bdr)),
      child: Column(children: [
        // 거치대
        _switchRow(
          icon: Icons.phonelink_rounded,
          title: '거치대 감지',
          subtitle: _cradleEnabled
            ? (cradle.isOnCradle ? '감지됨' : '미감지')
            : null,
          value: _cradleEnabled,
          onChanged: (v) { cradle.setEnabled(v); _safeSetState(() => _cradleEnabled = v); },
          trailing: _cradleEnabled ? GestureDetector(
            onTap: _calibrateCradle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _ac.withOpacity(0.3))),
              child: Text(cradle.isCalibrated ? '재측정' : '측정',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _ac)),
            ),
          ) : null,
        ),
        Divider(height: 1, color: _bdr),
        // 지오펜스 (자동 외출/귀가)
        _switchRow(
          icon: Icons.my_location_rounded,
          title: '자동 외출/귀가',
          subtitle: _geoEnabled
            ? (GeofenceService().hasHome
              ? (GeofenceService().isHome ? '집 (감지됨)' : '외출 중')
              : '집 위치 미설정')
            : 'GPS 기반 150m 반경',
          value: _geoEnabled,
          onChanged: (v) async {
            await GeofenceService().setEnabled(v);
            _safeSetState(() => _geoEnabled = v);
          },
          trailing: _geoEnabled ? GestureDetector(
            onTap: _setGeoHome,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _ac.withOpacity(0.3))),
              child: _geoSettingHome
                ? SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: _ac))
                : Text(GeofenceService().hasHome ? '재설정' : '집 설정',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _ac)),
            ),
          ) : null,
        ),
        Divider(height: 1, color: _bdr),
        // 무진동
        _switchRow(
          icon: Icons.vibration,
          title: '무진동 NFC',
          subtitle: '터치 시 진동 억제',
          value: _silentNfc,
          onChanged: _nfc.isAvailable ? (v) async {
            if (v) await _nfc.enableSilentReader();
            else await _nfc.disableSilentReader();
            _safeSetState(() => _silentNfc = _nfc.isSilentReaderEnabled);
          } : null,
        ),
      ]),
    );
  }

  Future<void> _setGeoHome() async {
    _safeSetState(() => _geoSettingHome = true);
    final ok = await GeofenceService().setHomeFromCurrentLocation();
    if (!mounted) return;
    _safeSetState(() => _geoSettingHome = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '집 위치 설정 완료!' : 'GPS 위치를 가져올 수 없습니다'),
      backgroundColor: ok ? BotanicalColors.success : BotanicalColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  Widget _switchRow({
    required IconData icon, required String title, String? subtitle,
    required bool value, ValueChanged<bool>? onChanged, Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Icon(icon, size: 18, color: _ac),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _main)),
        if (subtitle != null)
          Text(subtitle, style: TextStyle(fontSize: 10, color: _muted)),
      ])),
      if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
      SizedBox(height: 28, child: Switch(
        value: value, onChanged: onChanged,
        activeColor: _ac, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
    ]),
  );

  void _calibrateCradle() {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) {
      bool measuring = false, done = false;
      return StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('거치대 캘리브레이션'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (done) ...[
            const Icon(Icons.check_circle_rounded, size: 40, color: Color(0xFF10B981)),
            const SizedBox(height: 8),
            const Text('완료!'),
          ] else if (measuring) ...[
            const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 8),
            const Text('측정 중… (5초)'),
          ] else ...[
            Icon(Icons.phone_android_rounded, size: 40, color: _muted),
            const SizedBox(height: 8),
            const Text('폰을 거치대에 올려놓고\n측정을 시작하세요.', textAlign: TextAlign.center),
          ],
        ]),
        actions: [
          if (done)
            TextButton(onPressed: () { Navigator.pop(ctx); _safeSetState(() {}); },
              child: const Text('확인'))
          else if (!measuring) ...[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(onPressed: () async {
              setDlg(() => measuring = true);
              await CradleService().calibrate();
              setDlg(() { measuring = false; done = true; });
            }, child: const Text('측정 시작')),
          ],
        ],
      ));
    });
  }

  // ══════════ 수동 테스트 ══════════
  Widget _testTile() => Container(
    decoration: BoxDecoration(
      color: _card, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _bdr)),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      initiallyExpanded: false,
      title: Text('수동 테스트', style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1, color: _muted)),
      children: [
        Wrap(spacing: 6, runSpacing: 6,
          children: NfcTagRole.values.map((r) {
            final tag = NfcTagConfig(id: '', name: '', role: r, createdAt: '');
            return GestureDetector(
              onTap: () => _testRole(r),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _rc(r).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _rc(r).withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tag.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(tag.roleLabel.split(' ').first, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: _rc(r))),
                ]),
              ),
            );
          }).toList()),
      ],
    ),
  );

  // ══════════ 역할 요약 ══════════
  Widget _roleSummary() {
    final roles = [
      ('🚿', '기상', NfcTagRole.wake), ('🚪', '외출', NfcTagRole.outing),
      ('📚', '공부', NfcTagRole.study), ('🍽️', '식사', NfcTagRole.meal),
      ('🛏️', '취침', NfcTagRole.sleep),
    ];
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: roles.map((r) {
        final has = _nfc.tags.any((t) => t.role == r.$3);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 34, height: 34,
            decoration: BoxDecoration(
              color: has ? _ac.withOpacity(0.08) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: has ? Border.all(color: _ac.withOpacity(0.25)) : null),
            child: Center(child: Text(r.$1, style: TextStyle(fontSize: 14,
              color: has ? null : Colors.grey.withOpacity(0.4))))),
          const SizedBox(height: 3),
          Text(r.$2, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
            color: has ? _main : _muted.withOpacity(0.5))),
        ]);
      }).toList());
  }

  // ══════════ 빈 상태 ══════════
  Widget _empty() => Container(
    padding: const EdgeInsets.symmetric(vertical: 24),
    decoration: BoxDecoration(
      color: _card, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _bdr)),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.nfc_rounded, size: 28, color: _muted.withOpacity(0.3)),
      const SizedBox(height: 8),
      Text('등록된 태그 없음', style: TextStyle(fontSize: 12, color: _muted)),
    ])),
  );
}
