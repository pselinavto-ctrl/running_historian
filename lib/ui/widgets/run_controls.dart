import 'package:flutter/material.dart';

class RunControls extends StatelessWidget {
  const RunControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            backgroundColor: Colors.orange,
            onPressed: () {
              // Пауза
            },
            child: const Icon(Icons.pause),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            backgroundColor: Colors.green,
            onPressed: () {
              // Возобновление
            },
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            backgroundColor: Colors.red,
            onPressed: () {
              // Остановка
            },
            child: const Icon(Icons.stop),
          ),
        ],
      ),
    );
  }
}