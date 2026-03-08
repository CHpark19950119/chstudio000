import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// 텔레그램 서비스
/// - sendNfc: NFC 활동 알림 (양쪽 모두 전송)
/// - sendToMe: 나에게 시스템/배포/알람 알림
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

  // ─── NFC 활동 알림 (양쪽 모두) ───
  Future<void> sendNfc(String message) async {
    await Future.wait([
      _send(_myToken, _myChatId, message),
      _send(_gfToken, _gfChatId, message),
    ]);
  }

  Future<void> _send(String token, String chatId, String text) async {
    try {
      await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {'chat_id': chatId, 'text': text},
      );
      debugPrint('[Telegram] sent: $text');
    } catch (e) {
      debugPrint('[Telegram] send failed: $e');
    }
  }
}
