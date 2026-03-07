import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'theme/botanical_theme.dart';
import 'screens/splash_screen.dart';
import 'services/briefing_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const CheonhongApp());
}

class CheonhongApp extends StatefulWidget {
  const CheonhongApp({super.key});

  @override
  State<CheonhongApp> createState() => _CheonhongAppState();
}

/// 시간 기반 테마: 08:00~20:00 라이트, 그 외 다크
class _CheonhongAppState extends State<CheonhongApp>
    with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.dark;
  Timer? _themeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateTheme();
    // 매 분 테마 체크
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (_) => _updateTheme());
  }

  void _updateTheme() {
    final hour = DateTime.now().hour;
    final newMode = (hour >= 8 && hour < 20) ? ThemeMode.light : ThemeMode.dark;
    if (_themeMode != newMode) {
      setState(() => _themeMode = newMode);
      // 상태바 아이콘 색상 동기화
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            newMode == ThemeMode.light ? Brightness.dark : Brightness.light,
      ));
    }
  }

  @override
  void dispose() {
    _themeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BriefingService().ensureVolumeRestored();
      _updateTheme(); // 앱 복귀 시 테마도 갱신
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHEONHONG STUDIO',
      debugShowCheckedModeBanner: false,
      theme: BotanicalTheme.light(),
      darkTheme: BotanicalTheme.dark(),
      themeMode: _themeMode,
      home: const SplashScreen(),
    );
  }
}