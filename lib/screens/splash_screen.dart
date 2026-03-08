import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../app_init.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = AppInit.run();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(
              child: Lottie.asset(
                'assets/Book_Loader.json',
                width: 140,
                height: 140,
              ),
            ),
          );
        }
        return const HomeScreen();
      },
    );
  }
}