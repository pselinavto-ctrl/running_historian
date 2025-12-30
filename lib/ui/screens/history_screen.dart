import 'package:flutter/material.dart';
import 'package:running_historian/domain/run_session.dart';

class HistoryScreen extends StatelessWidget {
  final List<RunSession> history;

  const HistoryScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История пробежек')),
      body: history.isEmpty
          ? const Center(child: Text('Нет данных о пробежках'))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final session = history[history.length - 1 - index];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(
                      '${session.distance.toStringAsFixed(2)} км',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Факты: ${session.factsCount}'),
                  ),
                );
              },
            ),
    );
  }
}