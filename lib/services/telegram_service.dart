import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// 텔레그램 서비스
/// - sendToGf: 애인(다영)에게 NFC 활동 알림
/// - sendToMe:  나에게 시스템/배포/알람 알림
class TelegramService {
  static final TelegramService _instance = TelegramService._internal();
  factory TelegramService() => _instance;
  TelegramService._internal();

  // ── 내 봇 (시스템/배포/알람 알림) ──
  static const _myToken  = '8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo';
  static const _myChatId = '8724548311';

  // ── 애인 봇 (NFC 활동 알림) ──
  static const _gfToken  = '8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc';
  static const _gfChatId = '8624466505';

  // ─── 나에게 (배포 알림 등) ───
  Future<void> sendToMe(String message) async {
    await _send(_myToken, _myChatId, message);
  }

  // ─── 애인에게 (NFC 활동 알림) ───
  Future<void> sendToGf(String role, String timeStr) async {
    final messages = {
      'alarm':      '⏰ 천홍이 알람 울리고 있어요! $timeStr',
      'wake':       '천홍이 일어났어요 ☀️ $timeStr',
      'ready':      '천홍이 준비 완료했어요 🪥 $timeStr',
      'outing':     '천홍이 외출했어요 🚶 $timeStr',
      'study':      '천홍이 공부 시작했어요 📖 $timeStr',
      'study_end':  '천홍이 공부 끝났어요 📕 $timeStr',
      'meal_start': '천홍이 밥 먹어요 🍽️ $timeStr',
      'meal_end':   '천홍이 밥 다 먹었어요 🍽️ $timeStr',
      'sleep':      '천홍이 잠들었어요 🌙 $timeStr',
    };
    final msg = messages[role];
    if (msg == null) return;
    await _send(_gfToken, _gfChatId, msg);
  }

  Future<void> _send(String token, String chatId, String text) async {
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {'chat_id': chatId, 'text': text},
      );
      debugPrint('[Telegram] 전송: $text');
    } catch (e) {
      debugPrint('[Telegram] 전송 실패: $e');
    }
  }
}
