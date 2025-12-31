import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:running_historian/domain/run_session.dart';

class ResultsScreen extends StatelessWidget {
  final RunSession session;

  const ResultsScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Результаты')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: session.route.isNotEmpty
                  ? LatLng(session.route.first.lat, session.route.first.lon)
                  : const LatLng(47.2313, 39.7233),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.running_historian',
              ),
              if (session.route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: session.route.map((p) => LatLng(p.lat, p.lon)).toList(),
                      color: const Color(0xFF9C27B0),
                      strokeWidth: 8,
                    )
                  ],
                ),
            ],
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Дистанция: ${session.distance.toStringAsFixed(2)} км', style: const TextStyle(color: Colors.white)),
                  Text('Факты: ${session.factsCount}', style: const TextStyle(color: Colors.white)),
                  Text('Дата: ${formatDate(session.date)}', style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ),
        ],
      ),
    );
  }
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}