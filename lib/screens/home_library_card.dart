part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 부곡도서관 좌석 현황 카드
/// ═══════════════════════════════════════════════════
extension _HomeLibraryCard on _HomeScreenState {

  Future<void> _loadLibrary() async {
    final r = await LibraryService().fetch();
    _safeSetState(() => _libraryRoom = r);
  }

  Widget _libraryCard() {
    final r = _libraryRoom;
    final dk = _dk;

    if (r == null) {
      // 로딩 전 / 실패 시 — 탭하면 재시도
      return GestureDetector(
        onTap: _loadLibrary,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BotanicalDeco.card(dk),
          child: Row(children: [
            const Text('📚', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('부곡도서관', style: BotanicalTypo.body(
                size: 14, weight: FontWeight.w700, color: _textMain)),
              const SizedBox(height: 2),
              Text('탭하여 좌석 현황 불러오기', style: BotanicalTypo.label(
                size: 11, color: _textMuted)),
            ])),
            Icon(Icons.refresh_rounded, size: 18, color: _textMuted),
          ]),
        ),
      );
    }

    final pct = r.total > 0 ? r.used / r.total : 0.0;
    final statusColor = r.available <= 0
        ? const Color(0xFFEF4444)
        : r.available <= 5
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);
    final statusLabel = r.available <= 0
        ? '만석'
        : r.available <= 5
            ? '거의 만석'
            : '여유';
    final timeLabel =
        '${r.fetchedAt.hour.toString().padLeft(2, '0')}:${r.fetchedAt.minute.toString().padLeft(2, '0')} 기준';

    return GestureDetector(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LibrarySeatMapScreen()))
        .then((_) => _loadLibrary()),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BotanicalDeco.card(dk),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            const Text('📚', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('부곡도서관 일반열람실', style: BotanicalTypo.body(
                size: 13, weight: FontWeight.w700, color: _textMain)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(dk ? 0.15 : 0.10),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(statusLabel, style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w800, color: statusColor)),
                ),
                if (r.waiting > 0) ...[
                  const SizedBox(width: 6),
                  Text('대기 ${r.waiting}명', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange)),
                ],
              ]),
            ])),
            // Circular gauge
            SizedBox(width: 44, height: 44,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 3.5,
                  backgroundColor: dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation(statusColor.withOpacity(0.7)),
                ),
                Text('${(pct * 100).toInt()}%', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: statusColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ])),
          ]),
          const SizedBox(height: 12),
          // Big number row
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text('${r.available}', style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w900, color: statusColor,
              fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            Text('석 남음', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _textSub)),
            const Spacer(),
            Text('${r.used} / ${r.total}', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _textMuted,
              fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 8),
          // Footer
          Row(children: [
            Text(timeLabel, style: TextStyle(fontSize: 9, color: _textMuted.withOpacity(0.6))),
            const Spacer(),
            Row(children: [
              Text('좌석 배치도', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
              Icon(Icons.chevron_right_rounded, size: 14, color: _textMuted),
            ]),
          ]),
        ]),
      ),
    );
  }
}
