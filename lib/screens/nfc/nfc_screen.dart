import 'package:flutter/material.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/nfc_service.dart';

class NfcScreen extends StatefulWidget {
  const NfcScreen({super.key});
  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> with TickerProviderStateMixin {
  final _nfc = NfcService();

  // ─── 로컬 UI 상태 (ListenableBuilder 범위 밖) ───
  bool _isScanning = false;
  bool _registering = false;
  bool _isWritingNdef = false;
  bool _nfcLoading = true;
  String? _lastScannedUid;
  NfcTagConfig? _lastMatchedTag;
  String _statusMessage = '';
  NfcTagRole _selectedRole = NfcTagRole.wake;
  final _nameController = TextEditingController();

  late AnimationController _pulseController;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;
  Color get _card => _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _initNfc();
  }

  Future<void> _initNfc() async {
    await _nfc.initialize();
    if (mounted) setState(() => _nfcLoading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pulseController.dispose();
    _nfc.stopScan();
    super.dispose();
  }

  void _startScan({bool forRegister = false}) {
    if (!_nfc.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('이 기기는 NFC를 지원하지 않습니다.'),
        backgroundColor: BotanicalColors.error));
      return;
    }
    setState(() {
      _isScanning = true; _registering = forRegister;
      _lastScannedUid = null; _lastMatchedTag = null;
      _statusMessage = 'NFC 태그를 가까이 대주세요...';
    });
    _nfc.startScan(
      executeOnMatch: !forRegister,
      onDetected: (matched, uid) {
        if (!mounted) return;
        setState(() {
          _isScanning = false; _lastScannedUid = uid; _lastMatchedTag = matched;
          if (_registering) {
            if (matched != null) {
              _statusMessage = '이미 등록된 태그: ${matched.name}';
              _registering = false;
            } else {
              _statusMessage = '새 태그 감지됨';
            }
          } else {
            _statusMessage = matched != null
                ? '${matched.emoji} ${matched.roleLabel} 완료!'
                : '미등록 태그';
          }
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() { _isScanning = false; _statusMessage = error; });
      },
    );
  }

  Future<void> _registerTag() async {
    if (_lastScannedUid == null || _nameController.text.trim().isEmpty) return;
    final tag = await _nfc.registerTag(
      name: _nameController.text.trim(),
      role: _selectedRole,
      nfcUid: _lastScannedUid!,
    );
    if (!mounted) return;
    setState(() {
      _registering = false; _lastScannedUid = null;
      _nameController.clear();
      _statusMessage = '태그 등록 완료!';
    });
    _showNdefWriteDialog(tag);
  }

  void _showNdefWriteDialog(NfcTagConfig tag) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('NDEF 자동실행 쓰기', style: BotanicalTypo.heading(size: 18)),
      content: Text(
        '태그 터치 시 앱이 자동으로 열리고\n'
        '${tag.emoji} ${tag.roleLabel}이 실행됩니다.\n\n쓰시겠습니까?',
        style: BotanicalTypo.body()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('건너뛰기', style: TextStyle(color: _textMuted))),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); _writeNdef(tag); },
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('NDEF 쓰기', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  Future<void> _writeNdef(NfcTagConfig tag) async {
    setState(() { _isWritingNdef = true; _statusMessage = '태그를 가까이 대세요...'; });
    final success = await _nfc.writeNdefToTag(
      role: tag.role, tagId: tag.id,
      onStatus: (status) { if (mounted) setState(() => _statusMessage = status); },
    );
    if (!mounted) return;
    setState(() {
      _isWritingNdef = false;
      _statusMessage = success ? 'NDEF 쓰기 완료!' : 'NDEF 쓰기 실패';
    });
  }

  Future<void> _deleteTag(NfcTagConfig tag) async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('태그 삭제', style: BotanicalTypo.heading(size: 18)),
        content: Text('${tag.emoji} ${tag.name}을(를) 삭제하시겠습니까?', style: BotanicalTypo.body()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: TextStyle(color: _textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: BotanicalColors.error))),
        ],
      ));
    if (confirm == true) {
      await _nfc.removeTag(tag.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dk ? BotanicalColors.scaffoldDark : BotanicalColors.scaffoldLight,
      body: _nfcLoading
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 48, height: 48,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            const SizedBox(height: 16),
            Text('NFC 초기화 중...', style: BotanicalTypo.body(size: 14, color: _textMuted)),
          ]))
        : ListenableBuilder(
            listenable: _nfc,
            builder: (context, _) => _buildContent(),
          ),
    );
  }

  Widget _buildContent() {
    final tags = _nfc.tags;
    return CustomScrollView(slivers: [
      // ─── 앱바 ───
      SliverAppBar(
        pinned: true,
        backgroundColor: _dk ? BotanicalColors.scaffoldDark : BotanicalColors.scaffoldLight,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _textMain),
          onPressed: () => Navigator.pop(context)),
        title: Text('NFC', style: BotanicalTypo.heading(
          size: 20, weight: FontWeight.w800, color: _textMain)),
        centerTitle: false,
        actions: [
          if (_nfc.isAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BotanicalColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: BotanicalColors.success, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('NFC 활성', style: BotanicalTypo.label(
                    size: 10, weight: FontWeight.w600, color: BotanicalColors.success)),
                ]),
              ),
            ),
        ],
      ),

      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        sliver: SliverList(delegate: SliverChildListDelegate([
          if (!_nfc.isAvailable)
            _warningBanner('이 기기는 NFC를 지원하지 않습니다'),

          // ─── 상태 칩 ───
          _statusRow(),
          const SizedBox(height: 20),

          // ─── 스캔 허브 ───
          _scanHub(),
          const SizedBox(height: 24),

          // ─── 등록 폼 ───
          if (_registering && _lastScannedUid != null && _lastMatchedTag == null)
            _registerForm(),

          // ─── 등록된 태그 목록 ───
          Row(children: [
            Text('등록된 태그', style: BotanicalTypo.label(
              size: 11, weight: FontWeight.w700, letterSpacing: 1.5, color: _textMuted)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Text('${tags.length}', style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w800, color: _accent)),
            ),
          ]),
          const SizedBox(height: 12),
          if (tags.isEmpty)
            _emptyState()
          else
            ...tags.map((t) => _tagCard(t)),

          const SizedBox(height: 24),

          // ─── 수동 테스트 ───
          _manualTestSection(),

          const SizedBox(height: 24),

          // ─── NFC 태그 역할 요약 ───
          _nfcRoleSummary(),
        ])),
      ),
    ]);
  }

  // ══════════════════════════════════════════
  //  상태 칩 (외출/공부/식사)
  // ══════════════════════════════════════════

  Widget _statusRow() {
    return Row(children: [
      Expanded(child: _statusPill(
        emoji: '🚪', label: _nfc.isOut ? '외출 중' : '집',
        active: _nfc.isOut, color: const Color(0xFF3B8A6B),
      )),
      const SizedBox(width: 10),
      Expanded(child: _statusPill(
        emoji: '📚', label: _nfc.isStudying ? '공부 중' : '공부 대기',
        active: _nfc.isStudying, color: BotanicalColors.subjectVerbal,
      )),
      const SizedBox(width: 10),
      Expanded(child: _statusPill(
        emoji: '🍽️', label: _nfc.isMealing ? '식사 중' : '식사 대기',
        active: _nfc.isMealing, color: const Color(0xFFFF8A65),
      )),
    ]);
  }

  Widget _statusPill({
    required String emoji, required String label,
    required bool active, required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(_dk ? 0.12 : 0.06) : _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color.withOpacity(0.3) : _border,
          width: active ? 1.5 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(label, style: BotanicalTypo.label(
          size: 11, weight: FontWeight.w700,
          color: active ? color : _textMuted)),
        if (active) ...[
          const SizedBox(height: 4),
          Container(width: 6, height: 6,
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)])),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  스캔 허브
  // ══════════════════════════════════════════

  Widget _scanHub() {
    final bool busy = _isScanning || _isWritingNdef;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1E2D26), const Color(0xFF1A241E)]
            : [const Color(0xFFE8F0E8), const Color(0xFFF0F5EE)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withOpacity(0.15)),
      ),
      child: Column(children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08 + (_pulseController.value * (busy ? 0.08 : 0))),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withOpacity(busy ? 0.3 : 0.12))),
            child: Icon(Icons.nfc_rounded, size: 28, color: _accent),
          ),
        ),
        const SizedBox(height: 16),
        if (_statusMessage.isNotEmpty)
          Text(_statusMessage, textAlign: TextAlign.center,
            style: BotanicalTypo.body(size: 13, color: _textSub)),
        if (_statusMessage.isEmpty)
          Text('태그를 스캔하거나 새로 등록하세요', textAlign: TextAlign.center,
            style: BotanicalTypo.body(size: 13, color: _textMuted)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _actionBtn(
            icon: Icons.sensors_rounded,
            label: busy ? '스캔 중...' : '태그 스캔',
            filled: true,
            onTap: busy ? null : () => _startScan(),
          )),
          const SizedBox(width: 10),
          Expanded(child: _actionBtn(
            icon: Icons.add_rounded,
            label: '새 태그 등록',
            filled: false,
            onTap: busy ? null : () => _startScan(forRegister: true),
          )),
        ]),
      ]),
    );
  }

  Widget _actionBtn({
    required IconData icon, required String label,
    required bool filled, VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: filled ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: _accent.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16,
            color: filled ? Colors.white : _accent),
          const SizedBox(width: 6),
          Text(label, style: BotanicalTypo.label(
            size: 12, weight: FontWeight.w700,
            color: filled ? Colors.white : _accent)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  등록 폼
  // ══════════════════════════════════════════

  Widget _registerForm() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('새 태그 등록', style: BotanicalTypo.heading(size: 16, color: _textMain)),
        const SizedBox(height: 4),
        Text('UID: $_lastScannedUid',
          style: TextStyle(fontSize: 11, color: _textMuted, fontFamily: 'monospace')),
        const SizedBox(height: 16),
        TextField(controller: _nameController,
          decoration: InputDecoration(
            labelText: '태그 이름',
            hintText: '예: 욕실, 책상, 현관, 독서대',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        Text('역할', style: BotanicalTypo.label(
          size: 11, weight: FontWeight.w700, letterSpacing: 1, color: _textMuted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: NfcTagRole.values.map((role) => _roleChip(role)).toList()),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: GestureDetector(
          onTap: _nameController.text.trim().isNotEmpty ? _registerTag : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _nameController.text.trim().isNotEmpty
                ? _accent : _accent.withOpacity(0.3),
              borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text('등록하기', style: BotanicalTypo.label(
              size: 14, weight: FontWeight.w700, color: Colors.white))),
          ),
        )),
      ]),
    );
  }

  Widget _roleChip(NfcTagRole role) {
    final selected = _selectedRole == role;
    final tag = NfcTagConfig(id: '', name: '', role: role, createdAt: '');
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(_dk ? 0.15 : 0.08) : _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accent.withOpacity(0.4) : _border,
            width: selected ? 1.5 : 1)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(tag.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(tag.roleLabel.split(' ').first, style: BotanicalTypo.label(
            size: 12, weight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _accent : _textSub)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  태그 카드
  // ══════════════════════════════════════════

  Widget _tagCard(NfcTagConfig tag) {
    final roleColor = _roleColor(tag.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border)),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(
            color: roleColor.withOpacity(_dk ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(tag.emoji, style: const TextStyle(fontSize: 20)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tag.name, style: BotanicalTypo.body(
            size: 14, weight: FontWeight.w700, color: _textMain)),
          const SizedBox(height: 2),
          Text(tag.roleLabel, style: BotanicalTypo.label(size: 11, color: _textMuted)),
        ])),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: _textMuted, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) {
            if (v == 'test') _testTag(tag);
            if (v == 'ndef') _writeNdef(tag);
            if (v == 'delete') _deleteTag(tag);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'test',
              child: Row(children: [
                Icon(Icons.play_arrow_rounded, size: 18, color: _accent),
                const SizedBox(width: 8),
                const Text('수동 실행'),
              ])),
            PopupMenuItem(value: 'ndef',
              child: Row(children: [
                Icon(Icons.edit_note_rounded, size: 18, color: _accent),
                const SizedBox(width: 8),
                const Text('NDEF 쓰기'),
              ])),
            const PopupMenuItem(value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: BotanicalColors.error),
                SizedBox(width: 8),
                Text('삭제', style: TextStyle(color: BotanicalColors.error)),
              ])),
          ],
        ),
      ]),
    );
  }

  Future<void> _testTag(NfcTagConfig tag) async {
    final result = await _nfc.manualTestRole(tag.role);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${tag.emoji} $result'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Color _roleColor(NfcTagRole role) {
    switch (role) {
      case NfcTagRole.wake: return BotanicalColors.gold;
      case NfcTagRole.ready: return BotanicalColors.subjectVerbal;
      case NfcTagRole.outing: return const Color(0xFF3B8A6B);
      case NfcTagRole.study: return BotanicalColors.primary;
      case NfcTagRole.sleep: return const Color(0xFF5C6BC0);
      case NfcTagRole.meal: return const Color(0xFFFF8A65);
    }
  }

  // ══════════════════════════════════════════
  //  수동 테스트 섹션
  // ══════════════════════════════════════════

  Widget _manualTestSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('수동 테스트', style: BotanicalTypo.label(
          size: 11, weight: FontWeight.w700, letterSpacing: 1.5, color: _textMuted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8,
          children: NfcTagRole.values.map((role) {
            final tag = NfcTagConfig(id: '', name: '', role: role, createdAt: '');
            return GestureDetector(
              onTap: () async {
                final result = await _nfc.manualTestRole(role);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${tag.emoji} $result'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _roleColor(role).withOpacity(_dk ? 0.1 : 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _roleColor(role).withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tag.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(tag.roleLabel.split(' ').first, style: BotanicalTypo.label(
                    size: 12, weight: FontWeight.w600,
                    color: _roleColor(role))),
                ]),
              ),
            );
          }).toList()),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  빈 상태
  // ══════════════════════════════════════════

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border)),
      child: Column(children: [
        Icon(Icons.nfc_rounded, size: 40, color: _textMuted.withOpacity(0.4)),
        const SizedBox(height: 12),
        Text('등록된 태그가 없습니다', style: BotanicalTypo.body(
          size: 14, weight: FontWeight.w600, color: _textMuted)),
        const SizedBox(height: 4),
        Text('상단에서 새 태그를 등록해보세요', style: BotanicalTypo.label(
          size: 12, color: _textMuted.withOpacity(0.6))),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  NFC 역할 요약 (이모지)
  // ══════════════════════════════════════════

  Widget _nfcRoleSummary() {
    final roles = [
      ('🚿', '기상', NfcTagRole.wake),
      ('📖', '준비', NfcTagRole.ready),
      ('🚪', '외출', NfcTagRole.outing),
      ('📚', '공부', NfcTagRole.study),
      ('🍽️', '식사', NfcTagRole.meal),
      ('🛏️', '취침', NfcTagRole.sleep),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: roles.map((r) {
          final hasTag = _nfc.tags.any((t) => t.role == r.$3);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: hasTag
                  ? _accent.withOpacity(_dk ? 0.12 : 0.08)
                  : (_dk ? Colors.white.withOpacity(0.03) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: hasTag ? Border.all(color: _accent.withOpacity(0.3), width: 1) : null),
              child: Center(child: Text(r.$1, style: TextStyle(
                fontSize: 16,
                color: hasTag ? null : Colors.grey.withOpacity(0.4)))),
            ),
            const SizedBox(height: 4),
            Text(r.$2, style: BotanicalTypo.label(
              size: 9, weight: FontWeight.w600,
              color: hasTag ? _textMain : _textMuted.withOpacity(0.5))),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _warningBanner(String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BotanicalColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BotanicalColors.error.withOpacity(0.15))),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: BotanicalColors.error, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: BotanicalTypo.body(
          size: 13, color: BotanicalColors.error))),
      ]),
    );
  }
}
