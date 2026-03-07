import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../utils/study_date_utils.dart';
import 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — 식사 기록 + AI 칼로리 분석 v10
/// ═══════════════════════════════════════════════════════════
///
/// 사용자가 사진 + 음식 이름 입력
/// → OpenAI API로 칼로리/영양 분석
/// → Firebase 저장 + 캘린더 위젯 연동
class MealPhotoService {
  static final MealPhotoService _instance = MealPhotoService._internal();
  factory MealPhotoService() => _instance;
  MealPhotoService._internal();

  static const String _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';
  static const String _openaiUrl = 'https://api.openai.com/v1/chat/completions';

  final _picker = ImagePicker();
  final _storage = FirebaseStorage.instance;
  final _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════
  //  OpenAI API 키 관리
  // ═══════════════════════════════════════════

  Future<String?> getOpenAIKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('openai_api_key');
  }

  Future<void> setOpenAIKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openai_api_key', key.trim());
  }

  Future<bool> hasOpenAIKey() async {
    final key = await getOpenAIKey();
    return key != null && key.isNotEmpty && key.startsWith('sk-');
  }

  // ═══════════════════════════════════════════
  //  AI 칼로리 분석 (OpenAI GPT-4o-mini)
  // ═══════════════════════════════════════════

  /// 음식 이름 → 칼로리/영양 분석
  /// 반환: { 'calories': 520, 'protein': 25, 'carbs': 60, 'fat': 18, 'summary': '...' }
  Future<Map<String, dynamic>?> analyzeCalorie(String foodName) async {
    final apiKey = await getOpenAIKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[MealPhoto] ❌ OpenAI API 키 없음');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(_openaiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': '너는 영양사 AI야. 음식 이름을 받으면 1인분 기준 칼로리와 영양소를 추정해. '
                  '반드시 아래 JSON 형식으로만 응답해. 다른 텍스트 없이 JSON만:\n'
                  '{"calories":숫자,"protein":숫자,"carbs":숫자,"fat":숫자,"summary":"한줄 설명"}\n'
                  'calories는 kcal, protein/carbs/fat은 g 단위. '
                  '한국 음식 1인분 기준으로 추정해.',
            },
            {
              'role': 'user',
              'content': foodName,
            },
          ],
          'max_tokens': 150,
          'temperature': 0.3,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        // JSON 파싱 (```json 래핑 제거)
        final clean = content
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final result = jsonDecode(clean) as Map<String, dynamic>;
        debugPrint('[MealPhoto] 🔬 분석 완료: $foodName → ${result['calories']}kcal');
        return result;
      } else if (response.statusCode == 401) {
        debugPrint('[MealPhoto] ❌ API 키 유효하지 않음');
        return null;
      } else {
        debugPrint('[MealPhoto] ❌ API 응답 ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[MealPhoto] ❌ 칼로리 분석 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  카메라/갤러리
  // ═══════════════════════════════════════════

  Future<XFile?> capturePhoto() async {
    try {
      return await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800, maxHeight: 800, imageQuality: 65,
      );
    } catch (e) {
      debugPrint('[MealPhoto] ❌ 촬영 실패: $e');
      return null;
    }
  }

  Future<XFile?> pickFromGallery() async {
    try {
      return await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800, maxHeight: 800, imageQuality: 65,
      );
    } catch (e) {
      debugPrint('[MealPhoto] ❌ 갤러리 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  //  업로드
  // ═══════════════════════════════════════════

  Future<String?> uploadPhoto(XFile photo) async {
    const maxRetries = 3;
    final file = File(photo.path);
    if (!await file.exists()) return null;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'users/$_uid/mealPhotos/$timestamp.jpg';
        final ref = _storage.ref(path);

        debugPrint('[MealPhoto] 📤 시도 $attempt/$maxRetries');
        final snapshot = await ref.putFile(
          file, SettableMetadata(contentType: 'image/jpeg'),
        ).timeout(const Duration(seconds: 120));

        final url = await snapshot.ref.getDownloadURL();
        debugPrint('[MealPhoto] ✅ 업로드 완료');
        return url;
      } catch (e) {
        debugPrint('[MealPhoto] ❌ 실패 $attempt/$maxRetries: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 3));
        }
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  저장 + 캘린더 연동
  // ═══════════════════════════════════════════

  /// 학습일 계산 (4AM 경계)
  String _studyDate() => StudyDateUtils.todayKey();

  /// 식사 기록 저장 (칼로리 포함)
  Future<void> saveMealRecord({
    required String mealType,
    String photoUrl = '',
    String? foodName,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    String? summary,
    String? memo,
  }) async {
    final now = DateTime.now();
    final dateStr = _studyDate();
    final timeStr = DateFormat('HH:mm').format(now);

    final record = <String, dynamic>{
      'id': 'meal_${now.millisecondsSinceEpoch}',
      'mealType': mealType,
      'time': timeStr,
      'createdAt': now.toIso8601String(),
    };

    if (photoUrl.isNotEmpty) record['photoUrl'] = photoUrl;
    if (foodName != null) record['foodName'] = foodName;
    if (calories != null) record['calories'] = calories;
    if (protein != null) record['protein'] = protein;
    if (carbs != null) record['carbs'] = carbs;
    if (fat != null) record['fat'] = fat;
    if (summary != null) record['summary'] = summary;
    if (memo != null) record['memo'] = memo;

    // Firestore 저장
    await _db
        .collection('users/$_uid/mealRecords')
        .doc(dateStr)
        .set({
      'date': dateStr,
      'meals': FieldValue.arrayUnion([record]),
      '_updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // ★ 캘린더 연동: 일정으로 식사 기록 추가
    await _syncToCalendar(dateStr, mealType, foodName, calories);

    debugPrint('[MealPhoto] ✅ 저장: $mealType ${foodName ?? ''} ${calories ?? 0}kcal');
  }

  /// 캘린더에 식사 일정 동기화
  Future<void> _syncToCalendar(String date, String mealType, String? foodName, int? calories) async {
    try {
      final emoji = mealEmoji(mealType);
      final label = mealLabel(mealType);
      final calStr = calories != null ? ' ${calories}kcal' : '';
      final title = '$emoji$label${foodName != null ? ' $foodName' : ''}$calStr';

      // ★ Phase B: calendar 문서의 calendarEvents에 추가
      await _db.doc(FirebaseService.calendarDocPath).set({
        'calendarEvents': {
          date: {
            'meal_$mealType': {
              'title': title,
              'type': 'meal',
              'emoji': emoji,
            },
          },
        },
      }, SetOptions(merge: true));

      debugPrint('[MealPhoto] 📅 캘린더 동기화: $date → $title');
    } catch (e) {
      debugPrint('[MealPhoto] ⚠️ 캘린더 동기화 실패: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  삭제 / 수정
  // ═══════════════════════════════════════════

  /// 식사 기록 삭제 (id 기준)
  Future<void> deleteMealRecord(String mealId) async {
    final dateStr = _studyDate();
    try {
      final docRef = _db.collection('users/$_uid/mealRecords').doc(dateStr);
      final doc = await docRef.get();
      if (!doc.exists || doc.data() == null) return;

      final meals = (doc.data()!['meals'] as List<dynamic>?) ?? [];
      final target = meals.firstWhere(
        (m) => m is Map && m['id'] == mealId, orElse: () => null);
      if (target == null) return;

      // 캘린더에서도 삭제
      final mealType = target['mealType'] as String? ?? '';
      if (mealType.isNotEmpty) {
        await _removeFromCalendar(dateStr, mealType);
      }

      await docRef.update({
        'meals': FieldValue.arrayRemove([target]),
        '_updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[MealPhoto] 🗑️ 삭제: $mealId');
    } catch (e) {
      debugPrint('[MealPhoto] ❌ 삭제 실패: $e');
    }
  }

  /// 식사 기록 수정 (삭제 후 재저장)
  Future<void> updateMealRecord({
    required String mealId,
    required String mealType,
    String? foodName,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    String? summary,
    String? memo,
    String? photoUrl,
  }) async {
    final dateStr = _studyDate();
    try {
      final docRef = _db.collection('users/$_uid/mealRecords').doc(dateStr);
      final doc = await docRef.get();
      if (!doc.exists || doc.data() == null) return;

      final meals = List<dynamic>.from(
        (doc.data()!['meals'] as List<dynamic>?) ?? []);

      // 기존 기록 찾아서 수정
      final idx = meals.indexWhere((m) => m is Map && m['id'] == mealId);
      if (idx == -1) return;

      final old = Map<String, dynamic>.from(meals[idx] as Map);
      // 필드 업데이트
      old['mealType'] = mealType;
      if (foodName != null) old['foodName'] = foodName;
      if (calories != null) old['calories'] = calories;
      if (protein != null) old['protein'] = protein;
      if (carbs != null) old['carbs'] = carbs;
      if (fat != null) old['fat'] = fat;
      if (summary != null) old['summary'] = summary;
      if (memo != null) old['memo'] = memo;
      if (photoUrl != null && photoUrl.isNotEmpty) old['photoUrl'] = photoUrl;

      meals[idx] = old;

      await docRef.update({
        'meals': meals,
        '_updatedAt': FieldValue.serverTimestamp(),
      });

      // 캘린더 재동기화
      await _syncToCalendar(dateStr, mealType, foodName ?? old['foodName'], calories ?? old['calories']);

      debugPrint('[MealPhoto] ✏️ 수정: $mealId → $foodName ${calories}kcal');
    } catch (e) {
      debugPrint('[MealPhoto] ❌ 수정 실패: $e');
    }
  }

  /// 캘린더에서 식사 일정 삭제
  Future<void> _removeFromCalendar(String date, String mealType) async {
    try {
      // ★ Phase B: calendar 문서에서 삭제
      await _db.doc(FirebaseService.calendarDocPath).update({
        'calendarEvents.$date.meal_$mealType': FieldValue.delete(),
      });
      debugPrint('[MealPhoto] 📅 캘린더 삭제: $date meal_$mealType');
    } catch (e) {
      debugPrint('[MealPhoto] ⚠️ 캘린더 삭제 실패: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  조회
  // ═══════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getTodayMeals() async {
    final dateStr = _studyDate();
    try {
      final doc = await _db
          .collection('users/$_uid/mealRecords')
          .doc(dateStr)
          .get();
      if (!doc.exists || doc.data() == null) return [];
      final meals = doc.data()!['meals'] as List<dynamic>?;
      if (meals == null) return [];
      return meals.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[MealPhoto] 조회 실패: $e');
      return [];
    }
  }

  /// 오늘 총 칼로리
  Future<int> getTodayTotalCalories() async {
    final meals = await getTodayMeals();
    int total = 0;
    for (final m in meals) {
      total += (m['calories'] as int?) ?? 0;
    }
    return total;
  }

  // ═══════════════════════════════════════════
  //  유틸
  // ═══════════════════════════════════════════

  static String mealEmoji(String type) {
    switch (type) {
      case 'breakfast': return '🌅';
      case 'lunch': return '☀️';
      case 'dinner': return '🌙';
      case 'snack': return '🍪';
      default: return '🍽️';
    }
  }

  static String mealLabel(String type) {
    switch (type) {
      case 'breakfast': return '아침';
      case 'lunch': return '점심';
      case 'dinner': return '저녁';
      case 'snack': return '간식';
      default: return '식사';
    }
  }
}