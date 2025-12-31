import 'package:flutter/material.dart';

class DistancePanel extends StatelessWidget {
  final double distance;

  const DistancePanel({
    super.key,
    required this.distance,
  });

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
        child: Text(
          "🏃‍♂️ БЕГАЕМ!\nДистанция: ${distance.toStringAsFixed(2)} км",
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}