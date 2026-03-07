import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/order_models.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — 수험표 OCR 서비스 v1.0
/// Google Cloud Vision API → 텍스트 추출 → 구조화 파싱 → Firebase 저장
/// ═══════════════════════════════════════════════════════════
class ExamTicketService {
  static final ExamTicketService _instance = ExamTicketService._internal();
  factory ExamTicketService() => _instance;
  ExamTicketService._internal();

  static const String _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';
  static const String _visionUrl =
      'https://vision.googleapis.com/v1/images:annotate';

  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;
  final _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════
  //  Google Cloud Vision API 키 (하드코딩)
  // ═══════════════════════════════════════════

  static const String _apiKey = 'AIzaSyDIqOJ2Qh_wdwa8ZxVVzjZB-MecWjnog68';

  String? getGoogleApiKey() => _apiKey;
  bool hasGoogleApiKey() => true;

  // ═══════════════════════════════════════════
  //  이미지 선택
  // ═══════════════════════════════════════════

  Future<File?> pickImage({bool fromCamera = false}) async {
    final xFile = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    if (xFile == null) return null;
    return File(xFile.path);
  }

  // ═══════════════════════════════════════════
  //  Google Cloud Vision OCR
  // ═══════════════════════════════════════════

  /// 이미지 파일 → OCR 텍스트 추출
  /// v2: DOCUMENT_TEXT_DETECTION으로 테이블 구조 보존
  Future<String?> extractTextFromImage(File imageFile) async {
    final apiKey = getGoogleApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[ExamTicket] ❌ Google Cloud API 키 없음');
      return null;
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$_visionUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [
            {
              'image': {'content': base64Image},
              'features': [
                {'type': 'DOCUMENT_TEXT_DETECTION', 'maxResults': 1},
              ],
              'imageContext': {
                'languageHints': ['ko', 'en'],
              },
            },
          ],
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('[ExamTicket] ❌ Vision API Error: ${response.statusCode}');
        debugPrint('[ExamTicket] Body: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      final responses = data['responses'] as List?;
      if (responses == null || responses.isEmpty) return null;

      // DOCUMENT_TEXT_DETECTION → fullTextAnnotation 사용
      final fullAnno = responses[0]['fullTextAnnotation'];
      if (fullAnno != null) {
        final fullText = fullAnno['text'] as String?;
        debugPrint('[ExamTicket] ✅ DOCUMENT OCR 완료: ${fullText?.length ?? 0}자');
        return fullText;
      }

      // 폴백: textAnnotations
      final annotations = responses[0]['textAnnotations'] as List?;
      if (annotations == null || annotations.isEmpty) return null;

      final fullText = annotations[0]['description'] as String?;
      debugPrint('[ExamTicket] ✅ OCR 폴백 완료: ${fullText?.length ?? 0}자');
      return fullText;
    } catch (e) {
      debugPrint('[ExamTicket] ❌ OCR 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  OCR 텍스트 → 구조화 파싱
  // ═══════════════════════════════════════════

  /// OCR 원문에서 수험표 정보 추출
  /// v2: 2패스 파싱 — 라벨 줄 탐지 → 다음 비어있지 않은 줄 = 값
  ExamTicketInfo parseExamTicket(String ocrText) {
    final id = 'et_${DateTime.now().millisecondsSinceEpoch}';
    String? examName;
    String? examDate;
    String? examTime;
    String? location;
    String? seatNumber;
    String? examNumber;

    final lines = ocrText.split('\n').map((l) => l.trim()).toList();

    // ════════ 유틸: 라벨 줄 판별 ════════
    bool isLabelLine(String line) {
      return RegExp(r'(성명|생년월일|수험번호|응시번호|시험장|고사장|좌석|장소|시험일|시간|입실)').hasMatch(line);
    }

    // ════════ 유틸: 라벨 다음 값 찾기 ════════
    /// lines[i]에서 라벨이 감지되면, 같은 줄의 라벨 뒤 텍스트 또는
    /// 다음 비어있지 않은 줄을 값으로 반환
    String? findValueAfterLabel(int labelIdx, String label) {
      final line = lines[labelIdx];
      // 같은 줄에서 라벨 뒤 텍스트 탐색 (콜론/공백 구분)
      final afterLabel = line.replaceFirst(
        RegExp(RegExp.escape(label) + r'\s*[:：\s]\s*'), '').trim();
      if (afterLabel.isNotEmpty && afterLabel != line.trim()) {
        return afterLabel;
      }
      // 다음 비어있지 않은 줄
      for (int j = labelIdx + 1; j < lines.length && j <= labelIdx + 3; j++) {
        final next = lines[j].trim();
        if (next.isNotEmpty &&
            !isLabelLine(next)) { // 다음 라벨이 아닐 때만
          return next;
        }
      }
      return null;
    }

    // ════════ 1패스: 라벨 기반 키-값 추출 ════════

    final labelMap = <String, String>{};
    final labelPatterns = {
      '성명': RegExp(r'(성\s*명)'),
      '생년월일': RegExp(r'(생\s*년\s*월\s*일)'),
      '수험번호': RegExp(r'(수험\s*번호|응시\s*번호)'),
      '시험장': RegExp(r'(시험\s*장소?|고사\s*장|시험장)'),
      '좌석': RegExp(r'(좌석\s*번호?|좌석)'),
      '시험일': RegExp(r'(시험\s*일시?|시험\s*일자|시험\s*날짜)'),
      '시험시간': RegExp(r'(시험\s*시간|입실\s*시간|시작\s*시간|시간)'),
    };

    for (int i = 0; i < lines.length; i++) {
      for (final entry in labelPatterns.entries) {
        if (entry.value.hasMatch(lines[i]) && !labelMap.containsKey(entry.key)) {
          final val = findValueAfterLabel(i, entry.value.firstMatch(lines[i])!.group(0)!);
          if (val != null) {
            labelMap[entry.key] = val;
          }
        }
      }
    }

    // ════════ 2패스: 패턴 기반 추출 (라벨 매핑 실패 시 폴백) ════════

    // ── 시험명 추출 ──
    final examNamePatterns = [
      RegExp(r'([\w가-힣]+\s*(시험|고시|필기|PSAT|평가))', caseSensitive: false),
      RegExp(r'(제?\d+회?\s*[\w가-힣]+(시험|고시))'),
      RegExp(r'(공무원|공채|입법|국회|지방직|국가직|서울시).*(시험|필기|1차|2차)'),
      RegExp(r'(수험표|응시표|시험\s*안내)', caseSensitive: false),
    ];
    for (final line in lines) {
      for (final pat in examNamePatterns) {
        final m = pat.firstMatch(line);
        if (m != null && examName == null) {
          examName = m.group(0)?.trim();
          break;
        }
      }
      if (examName != null) break;
    }

    // ── 시험일자 추출 (유연 매칭) ──
    final datePatterns = [
      // 2026년 3월 7일, 2026.03.07, 2026-03-07, 2026/03/07
      RegExp(r'(\d{4})\s*[년.\-/]\s*(\d{1,2})\s*[월.\-/]\s*(\d{1,2})\s*일?'),
      // 3월 7일 (연도 없음)
      RegExp(r'(\d{1,2})\s*월\s*(\d{1,2})\s*일'),
    ];

    // 라벨 매핑에서 먼저 시도
    final dateSrc = labelMap['시험일'] ?? labelMap['생년월일'];
    if (dateSrc != null && examDate == null) {
      for (final pat in datePatterns) {
        final m = pat.firstMatch(dateSrc);
        if (m != null) {
          examDate = _extractDate(m);
          break;
        }
      }
    }
    // 전체 줄에서 탐색
    if (examDate == null) {
      for (final line in lines) {
        // 생년월일 줄 제외
        if (RegExp(r'생\s*년\s*월\s*일').hasMatch(line)) continue;
        for (final pat in datePatterns) {
          final m = pat.firstMatch(line);
          if (m != null) {
            examDate = _extractDate(m);
            break;
          }
        }
        if (examDate != null) break;
      }
    }

    // ── 시험시간 추출 (유연 매칭) ──
    final timePatterns = [
      RegExp(r'(\d{1,2})\s*[시:]\s*(\d{2})\s*분?'),
      RegExp(r'(\d{2}):(\d{2})'),
      RegExp(r'(오전|오후)\s*(\d{1,2})\s*시\s*(\d{0,2})'),
    ];

    // 라벨 매핑에서 먼저 시도
    final timeSrc = labelMap['시험시간'];
    if (timeSrc != null && examTime == null) {
      examTime = _extractTime(timeSrc, timePatterns);
    }
    // 시간 관련 키워드 포함 줄 우선
    if (examTime == null) {
      for (final line in lines) {
        if (line.contains('시간') || line.contains('입실') || line.contains('시작')) {
          examTime = _extractTime(line, timePatterns);
          if (examTime != null) break;
        }
      }
    }
    // 폴백: 시간 패턴이 있는 아무 라인
    if (examTime == null) {
      for (final line in lines) {
        final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(line);
        if (m != null) {
          final h = int.tryParse(m.group(1)!) ?? 0;
          if (h >= 7 && h <= 18) {
            examTime = '${m.group(1)!.padLeft(2, '0')}:${m.group(2)!}';
            break;
          }
        }
      }
    }

    // ── 시험장소 추출 ──
    location = labelMap['시험장'];
    if (location == null) {
      final locPatterns = [
        RegExp(r'(시험\s*장소?|고사\s*장|장소)\s*[:\s]*(.+)', caseSensitive: false),
        RegExp(r'(대학교?|고등학교|센터|회관|빌딩)\s*.*'),
      ];
      for (final line in lines) {
        for (final pat in locPatterns) {
          final m = pat.firstMatch(line);
          if (m != null && location == null) {
            location = m.groupCount >= 2
                ? m.group(2)?.trim()
                : m.group(0)?.trim();
            break;
          }
        }
        if (location != null) break;
      }
    }

    // ── 수험번호 추출 ──
    examNumber = labelMap['수험번호'];
    if (examNumber == null) {
      final numPatterns = [
        RegExp(r'(수험\s*번호|응시\s*번호)\s*[:\s]*(\S+)'),
        RegExp(r'번호\s*[:\s]*(\d[\d-]+)'),
      ];
      for (final line in lines) {
        for (final pat in numPatterns) {
          final m = pat.firstMatch(line);
          if (m != null && examNumber == null) {
            examNumber = m.group(m.groupCount)?.trim();
            break;
          }
        }
        if (examNumber != null) break;
      }
    }

    // ── 좌석번호 추출 ──
    seatNumber = labelMap['좌석'];
    if (seatNumber == null) {
      final seatPatterns = [
        RegExp(r'(좌석\s*번호?|좌석)\s*[:\s]*(\S+)'),
        RegExp(r'(\d+)\s*번\s*(좌석|자리)'),
      ];
      for (final line in lines) {
        for (final pat in seatPatterns) {
          final m = pat.firstMatch(line);
          if (m != null && seatNumber == null) {
            seatNumber = m.group(m.groupCount)?.trim();
            break;
          }
        }
        if (seatNumber != null) break;
      }
    }

    // 시험명 폴백
    examName ??= lines.isNotEmpty ? lines.first : '수험표';

    return ExamTicketInfo(
      id: id,
      examName: examName,
      examDate: examDate,
      examTime: examTime,
      location: location,
      seatNumber: seatNumber,
      examNumber: examNumber,
      rawOcrText: ocrText,
    );
  }

  /// 날짜 정규식 매치 → YYYY-MM-DD
  String? _extractDate(RegExpMatch m) {
    if (m.groupCount >= 3) {
      final y = m.group(1)!;
      final mo = m.group(2)!.padLeft(2, '0');
      final d = m.group(3)!.padLeft(2, '0');
      return '$y-$mo-$d';
    } else if (m.groupCount >= 2) {
      final now = DateTime.now();
      final mo = m.group(1)!.padLeft(2, '0');
      final d = m.group(2)!.padLeft(2, '0');
      return '${now.year}-$mo-$d';
    }
    return null;
  }

  /// 시간 추출 유틸
  String? _extractTime(String text, List<RegExp> patterns) {
    for (final pat in patterns) {
      final m = pat.firstMatch(text);
      if (m != null) {
        if (m.group(0)!.contains('오후')) {
          var h = (int.tryParse(m.group(2) ?? '0') ?? 0);
          if (h < 12) h += 12;
          final min = m.groupCount >= 3 ? (m.group(3) ?? '00') : '00';
          return '${h.toString().padLeft(2, '0')}:${min.padLeft(2, '0')}';
        } else if (m.group(0)!.contains('오전')) {
          final h = m.group(2)?.padLeft(2, '0') ?? '09';
          final min = m.groupCount >= 3 ? (m.group(3) ?? '00') : '00';
          return '$h:${min.padLeft(2, '0')}';
        } else {
          return '${m.group(1)?.padLeft(2, '0')}:${m.group(2)?.padLeft(2, '0')}';
        }
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  Firebase 저장/조회/삭제
  // ═══════════════════════════════════════════

  DocumentReference get _userDoc => _db.doc('users/$_uid');

  /// 이미지를 Firebase Storage에 업로드
  Future<String?> _uploadImage(File imageFile, String ticketId) async {
    try {
      final ref = _storage.ref('users/$_uid/exam_tickets/$ticketId.jpg');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('[ExamTicket] ❌ 이미지 업로드 실패: $e');
      return null;
    }
  }

  /// 수험표 정보 저장
  Future<void> saveTicket(ExamTicketInfo ticket) async {
    try {
      await _userDoc.set({
        'examTickets': {
          ticket.id: ticket.toMap(),
        },
      }, SetOptions(merge: true));
      debugPrint('[ExamTicket] ✅ 저장 완료: ${ticket.examName}');
    } catch (e) {
      debugPrint('[ExamTicket] ❌ 저장 실패: $e');
    }
  }

  /// 수험표 삭제
  Future<void> deleteTicket(String ticketId) async {
    try {
      await _userDoc.update({
        'examTickets.$ticketId': FieldValue.delete(),
      });
      // Storage 이미지도 삭제
      try {
        await _storage.ref('users/$_uid/exam_tickets/$ticketId.jpg').delete();
      } catch (_) {}
      debugPrint('[ExamTicket] ✅ 삭제 완료: $ticketId');
    } catch (e) {
      debugPrint('[ExamTicket] ❌ 삭제 실패: $e');
    }
  }

  /// 모든 수험표 조회
  Future<List<ExamTicketInfo>> loadAllTickets() async {
    try {
      final doc = await _userDoc.get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null || data['examTickets'] == null) return [];

      final raw = Map<String, dynamic>.from(data['examTickets'] as Map);
      return raw.entries.map((e) =>
          ExamTicketInfo.fromMap(Map<String, dynamic>.from(e.value as Map))
      ).toList()
        ..sort((a, b) {
          // D-Day 가까운 순으로 정렬
          final aD = a.daysLeft ?? 9999;
          final bD = b.daysLeft ?? 9999;
          return aD.compareTo(bD);
        });
    } catch (e) {
      debugPrint('[ExamTicket] ❌ 로딩 실패: $e');
      return [];
    }
  }

  /// 특정 날짜의 시험 조회
  Future<List<ExamTicketInfo>> ticketsForDate(String dateStr) async {
    final all = await loadAllTickets();
    return all.where((t) => t.examDate == dateStr).toList();
  }

  /// 다가오는 시험 (오늘 이후)
  Future<List<ExamTicketInfo>> upcomingTickets() async {
    final all = await loadAllTickets();
    return all.where((t) {
      final d = t.daysLeft;
      return d != null && d >= 0;
    }).toList();
  }

  // ═══════════════════════════════════════════
  //  OpenAI AI 해석 (OCR 텍스트 → 구조화)
  // ═══════════════════════════════════════════

  /// OCR 텍스트를 OpenAI GPT-4o-mini로 해석하여 구조화된 수험표 정보 추출
  Future<ExamTicketInfo?> aiParseExamTicket(String ocrText) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('openai_api_key');
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('[ExamTicket] ⚠️ OpenAI API 키 없음 → regex 폴백');
        return null;
      }

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'temperature': 0.1,
          'max_tokens': 500,
          'messages': [
            {
              'role': 'system',
              'content': '''당신은 한국 공무원 시험 수험표 OCR 텍스트를 구조화하는 전문가입니다.
아래 OCR 텍스트에서 수험표 정보를 추출하여 반드시 다음 JSON 형식으로만 응답하세요.
{
  "examName": "시험명 (예: 7급 국가공무원 공개경쟁채용 필기시험)",
  "examDate": "YYYY-MM-DD",
  "examTime": "HH:mm (24시간제)",
  "location": "시험장소",
  "seatNumber": "좌석번호",
  "examNumber": "수험번호",
  "applicantName": "응시자 성명"
}
추출할 수 없는 필드는 null로 표시. JSON만 반환하고 다른 텍스트는 포함하지 마세요.'''
            },
            {
              'role': 'user',
              'content': ocrText,
            },
          ],
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[ExamTicket] ❌ OpenAI API Error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      var content = data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return null;

      // 마크다운 코드블록 정리
      content = content.replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '').trim();

      final parsed = jsonDecode(content) as Map<String, dynamic>;
      debugPrint('[ExamTicket] ✅ AI 파싱 성공: ${parsed['examName']}');

      return ExamTicketInfo(
        id: 'et_${DateTime.now().millisecondsSinceEpoch}',
        examName: parsed['examName'] as String? ?? '수험표',
        examDate: parsed['examDate'] as String?,
        examTime: parsed['examTime'] as String?,
        location: parsed['location'] as String?,
        seatNumber: parsed['seatNumber'] as String?,
        examNumber: parsed['examNumber'] as String?,
        rawOcrText: ocrText,
      );
    } catch (e) {
      debugPrint('[ExamTicket] ⚠️ AI 파싱 실패 → regex 폴백: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  수험표 수정 (기존 ID 유지)
  // ═══════════════════════════════════════════

  /// 수험표 정보 업데이트 (수정 후 재저장)
  Future<void> updateTicket(ExamTicketInfo ticket) async {
    try {
      await _userDoc.set({
        'examTickets': {
          ticket.id: ticket.toMap(),
        },
      }, SetOptions(merge: true));
      debugPrint('[ExamTicket] ✅ 수정 완료: ${ticket.examName}');
    } catch (e) {
      debugPrint('[ExamTicket] ❌ 수정 실패: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  전체 플로우: 사진 → OCR → AI해석 → 저장
  // ═══════════════════════════════════════════

  /// 원스텝 처리: 이미지 선택 → OCR → AI 해석(우선) → regex 폴백 → 저장
  Future<ExamTicketInfo?> processExamTicket({bool fromCamera = false}) async {
    // 1. 이미지 선택
    final imageFile = await pickImage(fromCamera: fromCamera);
    if (imageFile == null) return null;

    // 2. OCR 실행
    final ocrText = await extractTextFromImage(imageFile);
    if (ocrText == null || ocrText.isEmpty) return null;

    // 3. AI 해석 우선 시도 → 실패 시 regex 폴백
    ExamTicketInfo? ticket = await aiParseExamTicket(ocrText);
    ticket ??= parseExamTicket(ocrText);

    // 4. 이미지 업로드
    final imageUrl = await _uploadImage(imageFile, ticket.id);
    if (imageUrl != null) ticket.imageUrl = imageUrl;

    // 5. Firebase 저장
    await saveTicket(ticket);

    return ticket;
  }
}