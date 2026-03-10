import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 좌석 상태
enum SeatStatus { available, standing, disabled, unavailable, inUse }

/// 좌석 정보
class LibraryRoom {
  final String name;
  final int total, used, available, waiting;
  final String rate;
  final Map<int, SeatStatus> seats;
  final DateTime fetchedAt;

  LibraryRoom({
    required this.name,
    required this.total,
    required this.used,
    required this.available,
    required this.waiting,
    required this.rate,
    required this.seats,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();
}

/// 부곡도서관 좌석 현황 크롤링 서비스
class LibraryService {
  static final LibraryService _i = LibraryService._();
  factory LibraryService() => _i;
  LibraryService._();

  static const _url = 'http://210.90.190.249:8081/RoomStatus.aspx';
  static const _cacheTtl = Duration(seconds: 30);

  LibraryRoom? _cache;
  DateTime? _cacheTime;

  LibraryRoom? get cached => _cache;

  String _decodeBody(List<int> bytes) {
    try { return utf8.decode(bytes); } catch (_) { return latin1.decode(bytes); }
  }

  Future<LibraryRoom?> fetch({bool force = false}) async {
    // 캐시 유효하면 반환
    if (!force && _cache != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      return _cache;
    }

    try {
      final uri = Uri.parse(_url);

      // Step 1: GET — ViewState 추출 (room 1이 기본 선택됨)
      final resp1 = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp1.statusCode != 200) {
        debugPrint('[Library] GET ${resp1.statusCode}');
        return _cache;
      }

      final body1 = _decodeBody(resp1.bodyBytes);

      // 요약 테이블은 GET 응답에 room 2 데이터 포함
      // 좌석 배치만 POST로 room 2를 가져와야 함

      // ViewState 추출
      final vs = RegExp(r'id="__VIEWSTATE"\s+value="([^"]*)"').firstMatch(body1)?.group(1) ?? '';
      final vg = RegExp(r'id="__VIEWSTATEGENERATOR"\s+value="([^"]*)"').firstMatch(body1)?.group(1) ?? '';
      final ev = RegExp(r'id="__EVENTVALIDATION"\s+value="([^"]*)"').firstMatch(body1)?.group(1) ?? '';

      // Step 2: POST — room 2 좌석 배치 가져오기
      final resp2 = await http.post(uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          '__VIEWSTATE': vs,
          '__VIEWSTATEGENERATOR': vg,
          '__VIEWSTATEENCRYPTED': '',
          '__EVENTVALIDATION': ev,
          'Roon_no': '2',
        },
      ).timeout(const Duration(seconds: 5));

      if (resp2.statusCode != 200) {
        debugPrint('[Library] POST ${resp2.statusCode}');
        // fallback: GET 응답에서 요약만이라도 파싱
        final room = _parse(body1);
        if (room != null) { _cache = room; _cacheTime = DateTime.now(); }
        return _cache;
      }

      final body2 = _decodeBody(resp2.bodyBytes);
      final room = _parse(body2);
      if (room != null) {
        _cache = room;
        _cacheTime = DateTime.now();
      }
      return _cache;
    } catch (e) {
      debugPrint('[Library] fetch error: $e');
      return _cache; // stale cache on error
    }
  }

  LibraryRoom? _parse(String html) {
    try {
      // (A) 요약 테이블 — data-room_no="2" 행
      final trMatch = RegExp(
        r'''data-room_no=["']2["'][^>]*>(.*?)</tr>''',
        dotAll: true,
      ).firstMatch(html);

      if (trMatch == null) {
        debugPrint('[Library] room_no=2 row not found');
        return null;
      }

      final trContent = trMatch.group(1)!;
      final tds = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(trContent)
          .map((m) => _stripHtml(m.group(1)!).trim())
          .toList();

      if (tds.length < 6) {
        debugPrint('[Library] insufficient td count: ${tds.length}');
        return null;
      }

      final name = tds[0].isNotEmpty ? tds[0] : '일반열람실';
      final total = int.tryParse(tds[1]) ?? 0;
      final used = int.tryParse(tds[2]) ?? 0;
      final avail = int.tryParse(tds[3]) ?? 0;
      final rate = tds[4];
      final waiting = int.tryParse(tds[5]) ?? 0;

      // (B) 좌석 배치 — room_content 영역 내 Style{N} normal_seat
      final seats = <int, SeatStatus>{};
      final roomIdx = html.indexOf('room_content');
      final seatHtml = roomIdx >= 0 ? html.substring(roomIdx) : html;
      final seatRegex = RegExp(
        r"class='Style(\d+)\s+normal_seat'[^>]*>\s*(\d+)",
        dotAll: true,
      );
      final seatMatches = seatRegex.allMatches(seatHtml);

      for (final m in seatMatches) {
        final styleStr = m.group(1)!;
        final seatNo = int.parse(m.group(2)!);
        seats[seatNo] = _styleToStatus(styleStr);
      }

      debugPrint('[Library] parsed: $name $avail/$total, seats=${seats.length}/84');
      return LibraryRoom(
        name: name, total: total, used: used, available: avail,
        waiting: waiting, rate: rate, seats: seats,
      );
    } catch (e) {
      debugPrint('[Library] parse error: $e');
      return null;
    }
  }

  static SeatStatus _styleToStatus(String style) {
    switch (style) {
      case '1': return SeatStatus.available;
      case '2': return SeatStatus.standing;
      case '8': return SeatStatus.disabled;
      case '9': return SeatStatus.unavailable;
      case '10': return SeatStatus.inUse;
      default: return SeatStatus.unavailable;
    }
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ');
}
