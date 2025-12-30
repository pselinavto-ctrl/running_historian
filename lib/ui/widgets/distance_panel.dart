import 'package:flutter/material.dart';

class DistancePanel extends StatelessWidget {
  const DistancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          "🏃‍♂️ БЕГАЕМ!\nДистанция: 0.00 км",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
