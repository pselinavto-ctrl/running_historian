import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/listened_fact.dart';
import '../../services/listened_history_service.dart';
import '../../services/tts_service.dart';
import '../../services/audio_service.dart';

class FactHistoryScreen extends StatefulWidget {
  const FactHistoryScreen({super.key});

  @override
  State<FactHistoryScreen> createState() => _FactHistoryScreenState();
}

class _FactHistoryScreenState extends State<FactHistoryScreen> {
  final ListenedHistoryService _historyService = ListenedHistoryService();
  late final TtsService _tts;
  
  @override
  void initState() {
    super.initState();
    _tts = TtsService(AudioService())..init();
  }
  
  @override
  void dispose() {
    _tts.dispose(); // 👈 ОБЯЗАТЕЛЬНОЕ ОСВОБОЖДЕНИЕ РЕСУРСОВ
    super.dispose();
  }
  
  // ... остальной код остается тем же ...
  
  void _showTtsDialog(String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Воспроизведение'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await _tts.speak(text);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.volume_up),
            label: const Text('Воспроизвести'),
          ),
        ],
      ),
    );
  }
}