import 'package:flutter/material.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/ui/screens/results_screen.dart';

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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Факты: ${session.factsCount}'),
                        Text('Дата: ${formatDate(session.date)}'),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ResultsScreen(session: session)),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}