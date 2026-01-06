import 'package:flutter/material.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/ui/screens/session_detail_screen.dart'; // 👈 Новый экран

class HistoryScreen extends StatelessWidget {
  final List<RunSession> history;

  const HistoryScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История пробежек')),
      body: ListView.builder(
        itemCount: history.length,
        itemBuilder: (context, index) {
          final session = history[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text('${session.distance.toStringAsFixed(2)} км'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Факты: ${session.factsCount}'),
                  Text('Дата: ${session.date.toIso8601String().split('T')[0]}'),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SessionDetailScreen(session: session),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}