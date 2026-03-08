import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — Premium Study Room Theme v9.3
/// ═══════════════════════════════════════════════════════════
///
/// 컨셉: 밝은 원목 독서실 · 햇살 북카페 · 포근 · 차분 · 몰입
/// Light: 따뜻한 크림 + 꿀빛 원목 + 소프트 세이지 그린
/// Dark: 따뜻한 다크우드 (차가운 느낌 배제, 갈색 기조 유지)

class BotanicalColors {
  BotanicalColors._();

  // ─── Primary: 소프트 세이지 그린 (밝고 부드럽게) ───
  static const primary = Color(0xFF3A6B3A);
  static const primaryLight = Color(0xFF5A8C5A);
  static const primaryMuted = Color(0xFF7FA87F);
  static const primarySurface = Color(0xFFE8F2E8);

  // ─── Accent: 꿀빛 골드 (따뜻하고 밝게) ───
  static const gold = Color(0xFFC49032);
  static const goldLight = Color(0xFFDAAA4E);
  static const goldMuted = Color(0xFFE8CFA0);
  static const goldSurface = Color(0xFFFFF8EC);

  // ─── Light Mode: 햇살 크림 ───
  static const scaffoldLight = Color(0xFFFCF9F3);   // 따뜻한 밀크 크림
  static const cardLight = Color(0xFFFFFFFA);        // 순백에 가까운 크림
  static const surfaceLight = Color(0xFFF5EFE5);     // 꿀빛 베이지
  static const borderLight = Color(0xFFEAE0D2);      // 부드러운 원목 테두리
  static const textMain = Color(0xFF2C2218);          // 따뜻한 다크 브라운
  static const textSub = Color(0xFF6B5D4E);           // 우드 브라운
  static const textMuted = Color(0xFF9C8E7E);         // 소프트 그레이지
  static const textHint = Color(0xFFBDB0A0);          // 힌트

  // ─── Dark Mode: 따뜻한 다크 우드 ───
  static const scaffoldDark = Color(0xFF1A1612);      // 따뜻한 다크 (검지 않게)
  static const cardDark = Color(0xFF241E18);          // 따뜻한 우드
  static const surfaceDark = Color(0xFF2E261E);       // 원목 패널
  static const borderDark = Color(0xFF3D3228);        // 나무결 테두리
  static const textMainDark = Color(0xFFF5EDE4);      // 크림 화이트
  static const textSubDark = Color(0xFFCBB89E);       // 골든 베이지
  static const textMutedDark = Color(0xFF998A7A);     // 뮤트 브라운
  static const lanternGold = Color(0xFFDAAA4E);       // 따뜻한 골드

  // ─── 과목 컬러 (밝고 부드러운 톤) ───
  static const subjectData = Color(0xFF4A8A60);       // 자료해석: 밝은 세이지
  static const subjectVerbal = Color(0xFF5B6ABF);     // 언어논리: 라벤더 블루
  static const subjectSituation = Color(0xFFD4893B);  // 상황판단: 앰버
  static const subjectConst = Color(0xFF8B5A72);      // 헌법: 로즈우드
  static const subjectEnglish = Color(0xFF4A90A8);    // 영어: 스카이 틸

  // ─── 시맨틱 ───
  static const success = Color(0xFF4A8A60);
  static const warning = Color(0xFFD4893B);
  static const error = Color(0xFFBF4A4A);
  static const info = Color(0xFF4A90A8);

  // ─── 등급 컬러 ───
  static const gradeSPlus = Color(0xFFDAAA4E);        // 꿀빛 골드
  static const gradeS = Color(0xFF3A6B3A);
  static const gradeA = Color(0xFF4A8A60);
  static const gradeB = Color(0xFF4A90A8);
  static const gradeC = Color(0xFFD4893B);
  static const gradeD = Color(0xFFBF4A4A);
  static const gradeF = Color(0xFF8A7B6B);

  static Color subjectColor(String subject) {
    switch (subject) {
      case '자료해석': return subjectData;
      case '언어논리': return subjectVerbal;
      case '상황판단': return subjectSituation;
      case '헌법': return subjectConst;
      case '영어': return subjectEnglish;
      default: return primaryMuted;
    }
  }

  static Color gradeColor(String grade) {
    switch (grade) {
      case 'S+': return gradeSPlus;
      case 'S': return gradeS;
      case 'A': return gradeA;
      case 'B': return gradeB;
      case 'C': return gradeC;
      case 'D': return gradeD;
      default: return gradeF;
    }
  }

  static List<Color> weatherGradient(String main) {
    switch (main.toLowerCase()) {
      case 'clear': return [const Color(0xFF5B9A72), const Color(0xFF7AB897)];
      case 'clouds': return [const Color(0xFF8A7B6B), const Color(0xFFA09080)];
      case 'rain': case 'drizzle': return [const Color(0xFF5A7A85), const Color(0xFF7A9AA0)];
      case 'thunderstorm': return [const Color(0xFF3A3028), const Color(0xFF5A4D40)];
      case 'snow': return [const Color(0xFFC0B5A5), const Color(0xFFDDD2C5)];
      default: return [const Color(0xFF5B9A72), const Color(0xFF7AAA88)];
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Typography
// ═══════════════════════════════════════════════════════════

class BotanicalTypo {
  BotanicalTypo._();

  static TextStyle heading({
    double size = 18,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => GoogleFonts.notoSerifKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textMain,
    height: 1.3,
  );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => GoogleFonts.notoSansKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textMain,
    height: 1.4,
  );

  static TextStyle label({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) => GoogleFonts.notoSansKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textSub,
    letterSpacing: letterSpacing,
    height: 1.3,
  );

  static TextStyle number({
    double size = 48,
    FontWeight weight = FontWeight.w200,
    Color? color,
  }) => GoogleFonts.notoSerifKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textMain,
    height: 1.1,
  );

  static TextStyle brand({double size = 12, Color? color}) =>
      GoogleFonts.notoSerifKr(
        fontSize: size, fontWeight: FontWeight.w700,
        letterSpacing: 3,
        color: color ?? BotanicalColors.primary,
      );
}

// ═══════════════════════════════════════════════════════════
// Component Decorations
// ═══════════════════════════════════════════════════════════

class BotanicalDeco {
  BotanicalDeco._();

  /// 기본 카드 — 밝고 깨끗한 노트카드
  static BoxDecoration card(bool dark, {Color? color, double radius = 22}) =>
      BoxDecoration(
        color: color ?? (dark ? BotanicalColors.cardDark : BotanicalColors.cardLight),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
            ? BotanicalColors.borderDark.withOpacity(0.6)
            : BotanicalColors.borderLight.withOpacity(0.5),
          width: 0.5,
        ),
        boxShadow: dark
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 20, offset: const Offset(0, 6)),
            ]
          : [
              // 라이트: 꿀빛 따뜻한 그림자
              BoxShadow(
                color: const Color(0xFFCBB89E).withOpacity(0.12),
                blurRadius: 24, offset: const Offset(0, 8)),
              BoxShadow(
                color: const Color(0xFFCBB89E).withOpacity(0.04),
                blurRadius: 40, offset: const Offset(0, 16)),
            ],
      );

  /// 서재 다크 카드
  static BoxDecoration libraryCard({double radius = 22}) => BoxDecoration(
    color: BotanicalColors.cardDark,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BotanicalColors.borderDark),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 8)),
    ],
  );

  static BoxDecoration iconBox(Color color, bool dark, {double radius = 14}) =>
      BoxDecoration(
        color: color.withOpacity(dark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withOpacity(0.1), width: 0.5),
      );

  static BoxDecoration badge(Color color, {double radius = 20}) => BoxDecoration(
    color: color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: color.withOpacity(0.2)),
  );

  static BoxDecoration selectedChip(Color color, bool dark, {double radius = 14}) =>
      BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      );

  static BoxDecoration unselectedChip(bool dark, {double radius = 14}) =>
      BoxDecoration(
        color: dark ? BotanicalColors.surfaceDark : BotanicalColors.cardLight,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? BotanicalColors.borderDark : BotanicalColors.borderLight),
      );

  static BoxDecoration innerInfo(bool dark, {double radius = 16}) => BoxDecoration(
    color: dark ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: dark ? BotanicalColors.borderDark : BotanicalColors.borderLight, width: 0.5),
  );

  /// ★ 포근한 글래스 카드
  static BoxDecoration warmGlass(bool dark, {double radius = 22}) => BoxDecoration(
    color: dark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.6),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: dark ? BotanicalColors.borderDark.withOpacity(0.5) : BotanicalColors.borderLight.withOpacity(0.4)),
    boxShadow: [BoxShadow(
      color: dark ? Colors.black.withOpacity(0.15)
        : const Color(0xFFCBB89E).withOpacity(0.08),
      blurRadius: 16, offset: const Offset(0, 4))],
  );
}

// ═══════════════════════════════════════════════════════════
// 성장 메타포 시각화
// ═══════════════════════════════════════════════════════════

class GrowthMetaphor {
  GrowthMetaphor._();

  static ({String emoji, String label, String desc}) streakStage(int days) {
    if (days >= 100) return (emoji: '🌳', label: '거목', desc: '흔들리지 않는 뿌리');
    if (days >= 60)  return (emoji: '🌲', label: '큰 나무', desc: '굳건한 성장');
    if (days >= 30)  return (emoji: '🌿', label: '풀숲', desc: '안정적인 습관');
    if (days >= 14)  return (emoji: '🌱', label: '새싹', desc: '습관이 자라는 중');
    if (days >= 7)   return (emoji: '🫒', label: '씨앗', desc: '뿌리를 내리는 중');
    if (days >= 1)   return (emoji: '🌰', label: '씨앗', desc: '첫 발아');
    return (emoji: '💤', label: '휴면', desc: '새 시작을 기다리는 중');
  }

  static String gradeFlower(String grade) {
    switch (grade) {
      case 'S+': return '🌺';
      case 'S': return '🌸';
      case 'A': return '🌷';
      case 'B': return '🌼';
      case 'C': return '🌻';
      case 'D': return '🥀';
      default: return '🍂';
    }
  }

  static ({String emoji, String label, double fill}) waterLevel(int minutes) {
    if (minutes >= 480) return (emoji: '💧💧💧', label: '충분한 관수', fill: 1.0);
    if (minutes >= 360) return (emoji: '💧💧', label: '적정 관수', fill: minutes / 480);
    if (minutes >= 240) return (emoji: '💧', label: '기본 관수', fill: minutes / 480);
    if (minutes >= 120) return (emoji: '🫗', label: '부족', fill: minutes / 480);
    return (emoji: '🏜️', label: '가뭄', fill: minutes / 480);
  }

  static String progressPlant(double ratio) {
    if (ratio >= 1.0) return '🌳';
    if (ratio >= 0.8) return '🌿';
    if (ratio >= 0.6) return '🌱';
    if (ratio >= 0.4) return '☘️';
    if (ratio >= 0.2) return '🫒';
    return '🌰';
  }
}

// ═══════════════════════════════════════════════════════════
// ThemeData builders
// ═══════════════════════════════════════════════════════════

class BotanicalTheme {
  BotanicalTheme._();

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: BotanicalColors.primary,
    scaffoldBackgroundColor: BotanicalColors.scaffoldLight,
    textTheme: GoogleFonts.notoSansKrTextTheme(),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      color: BotanicalColors.cardLight,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: BotanicalColors.scaffoldLight,
      elevation: 0, scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.notoSerifKr(
        fontSize: 18, fontWeight: FontWeight.w700, color: BotanicalColors.textMain),
      iconTheme: const IconThemeData(color: BotanicalColors.textSub),
    ),
    dividerColor: BotanicalColors.borderLight,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BotanicalColors.primary, linearTrackColor: BotanicalColors.surfaceLight),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.primary : BotanicalColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.primarySurface : BotanicalColors.surfaceLight),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: BotanicalColors.gold, thumbColor: BotanicalColors.gold,
      inactiveTrackColor: BotanicalColors.surfaceLight),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFFFCF9F3),
      selectedItemColor: BotanicalColors.primary,
      unselectedItemColor: BotanicalColors.textMuted, elevation: 0),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: BotanicalColors.primary,
    scaffoldBackgroundColor: BotanicalColors.scaffoldDark,
    textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      color: BotanicalColors.cardDark,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: BotanicalColors.scaffoldDark,
      elevation: 0, scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.notoSerifKr(
        fontSize: 18, fontWeight: FontWeight.w700, color: BotanicalColors.textMainDark),
      iconTheme: const IconThemeData(color: BotanicalColors.textSubDark),
    ),
    dividerColor: BotanicalColors.borderDark,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BotanicalColors.lanternGold, linearTrackColor: BotanicalColors.surfaceDark),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.lanternGold : BotanicalColors.textMutedDark),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.surfaceDark : BotanicalColors.cardDark),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: BotanicalColors.lanternGold, thumbColor: BotanicalColors.lanternGold,
      inactiveTrackColor: BotanicalColors.surfaceDark),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1612),
      selectedItemColor: BotanicalColors.lanternGold,
      unselectedItemColor: BotanicalColors.textMutedDark, elevation: 0),
  );
}

// ═══ GLOBAL BOTTOM SHEET SAFE PADDING ═══
/// 바텀시트 안전 하단 패딩: 키보드 또는 시스템 네비바 높이 + 여유
double sheetBottomPad(BuildContext ctx, {double extra = 20}) {
  final mq = MediaQuery.of(ctx);
  final kbOrNav = mq.viewInsets.bottom > 0
      ? mq.viewInsets.bottom
      : mq.viewPadding.bottom;
  return kbOrNav + extra;
}
