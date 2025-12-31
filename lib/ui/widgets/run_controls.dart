import 'package:flutter/material.dart';

class RunControls extends StatelessWidget {
  final bool isRunning;
  final bool isPaused;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  const RunControls({
    super.key,
    required this.isRunning,
    required this.isPaused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRunning) {
      return Positioned(
        bottom: 20,
        right: 20,
        child: FloatingActionButton(
          backgroundColor: Colors.green,
          onPressed: onStart,
          child: const Icon(Icons.play_arrow),
        ),
      );
    }

    if (isPaused) {
      return Positioned(
        bottom: 20,
        right: 20,
        child: FloatingActionButton(
          backgroundColor: Colors.green,
          onPressed: onResume,
          child: const Icon(Icons.play_arrow),
        ),
      );
    }

    return Positioned(
      bottom: 20,
      right: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            backgroundColor: Colors.orange,
            onPressed: onPause,
            child: const Icon(Icons.pause),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            backgroundColor: Colors.red,
            onPressed: onStop,
            child: const Icon(Icons.stop),
          ),
        ],
      ),
    );
  }
}