import 'package:flutter/material.dart';
import '../game/creature_component.dart';

class CreatureFloatButton extends StatelessWidget {
  final int level;
  final int stage;
  final VoidCallback onTap;

  const CreatureFloatButton({
    super.key,
    required this.level,
    required this.stage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.4),
            blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Center(child: CustomPaint(
            size: const Size(36, 36),
            painter: MiniCreaturePainter(stage: stage),
          )),
          Positioned(top: -4, right: -4, child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2)),
            child: Center(child: Text('$level',
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)))),
          )),
        ]),
      ),
    );
  }
}
