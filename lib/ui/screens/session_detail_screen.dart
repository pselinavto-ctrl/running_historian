import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/domain/landmark.dart';
import 'package:running_historian/domain/route_point.dart'; // 👈 Импорт

class SessionDetailScreen extends StatelessWidget {
  final RunSession session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Детали сессии')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Дистанция: ${session.distance.toStringAsFixed(2)} км'),
                Text('Факты: ${session.factsCount}'),
                Text('Дата: ${session.date.toIso8601String().split('T')[0]}'),
              ],
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                mapController: MapController(),
                options: MapOptions(
                  initialCenter: session.route.isNotEmpty
                      ? LatLng(session.route.first.lat, session.route.first.lon)
                      : const LatLng(47.2313, 39.7233),
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.running_historian',
                  ),
                  if (session.route.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        // 👇 ГРАДИЕНТНЫЙ ТРЕК В ДЕТАЛЯХ
                        ..._buildSpeedPolylines(session.route),
                      ],
                    ),
                  if (session.route.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                            session.route.first.lat,
                            session.route.first.lon,
                          ),
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        Marker(
                          point: LatLng(
                            session.route.last.lat,
                            session.route.last.lon,
                          ),
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.flag,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: kLandmarks.map((landmark) {
                      return Marker(
                        point: LatLng(landmark.lat, landmark.lon),
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // 👇 НОВОЕ: градиентный трек для деталей
  List<Polyline> _buildSpeedPolylines(List<RoutePoint> route) {
    final polylines = <Polyline>[];

    for (int i = 1; i < route.length; i++) {
      final p1 = route[i - 1];
      final p2 = route[i];

      Color color;
      if (p1.speed < 2) {
        color = Colors.blue;
      } else if (p1.speed < 5) {
        color = const Color(0xFF9C27B0); // фиолетовый
      } else {
        color = Colors.red;
      }

      polylines.add(
        Polyline(
          points: [LatLng(p1.lat, p1.lon), LatLng(p2.lat, p2.lon)],
          strokeWidth: 5,
          color: color,
        ),
      );
    }

    return polylines;
  }
}
