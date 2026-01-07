import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/landmark.dart'; // 👈 ДОБАВЛЕН ИМПОРТ LANDMARKS
import 'package:running_historian/config/constants.dart'; // 👈 ДОБАВЛЕН ИМПОРТ КОНСТАНТ
import 'package:running_historian/domain/landmark.dart';
import 'dart:math' as math;

class SessionDetailScreen extends StatelessWidget {
  final RunSession session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали пробежки'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              _shareResults(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 👇 СТАТИСТИКА СЕССИИ
          _buildStatsPanel(),
          // 👇 КАРТА С ТРЕКОМ
          Expanded(
            child: SizedBox(
              height: 300,
              child: FlutterMap(
                mapController: MapController(),
                options: MapOptions(
                  initialCenter: session.route.isNotEmpty
                      ? LatLng(session.route.first.lat, session.route.first.lon)
                      : const LatLng(47.2313, 39.7233),
                  initialZoom: 13,
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
                        // 👇 ГРАДИЕНТНЫЙ ТРЕК
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
                        Marker(
                          point: LatLng(
                            session.route.last.lat,
                            session.route.last.lon,
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
                      ],
                    ),
                  // 👇 ИМПОРТИРОВАННЫЕ ПАМЯТНИКИ
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
          // 👇 КНОПКИ ДЕЙСТВИЙ
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildStatsPanel() {
    final duration = Duration(seconds: session.duration);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    // 👇 РАСЧЁТ ТЕМПА
    final pace = session.distance > 0
        ? (session.duration / session.distance)
        : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();

    // 👇 РАСЧЁТ КАЛОРИЙ (примерная модель)
    final calories = (session.distance * 70).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.withOpacity(0.1),
            Colors.indigo.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // 👇 ОСНОВНАЯ СТАТИСТИКА
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard(
                'Дистанция',
                '${session.distance.toStringAsFixed(1)} км',
                Icons.route,
              ),
              _buildStatCard(
                'Время',
                hours > 0
                    ? '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
                    : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                Icons.access_time,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 👇 ДОПОЛНИТЕЛЬНАЯ СТАТИСТИКА
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard(
                'Темп',
                '$paceMinutes:${paceSeconds.toString().padLeft(2, '0')} мин/км',
                Icons.speed,
                color: pace < 6
                    ? Colors.green
                    : pace < 8
                    ? Colors.orange
                    : Colors.red,
              ),
              _buildStatCard(
                'Калории',
                '$calories',
                Icons.local_fire_department,
                color: Colors.orange,
              ),
              _buildStatCard(
                'Факты',
                session.factsCount.toString(),
                Icons.menu_book,
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color ?? Colors.deepPurple),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton('Повторить', Icons.replay, () {
            Navigator.pop(context);
            // Логика повторения тренировки
          }, color: Colors.blue),
          _buildActionButton('Удалить', Icons.delete, () {
            _showDeleteConfirmation(context);
          }, color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    VoidCallback onPressed, {
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(text, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(140, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        shadowColor: color.withOpacity(0.5),
      ),
    );
  }

  void _shareResults(BuildContext context) {
    final duration = Duration(seconds: session.duration);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final pace = session.distance > 0
        ? (session.duration / session.distance)
        : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();

    // 👇 ДОБАВЛЕН РАСЧЁТ КАЛОРИЙ В ЭТОМ МЕТОДЕ
    final calories = (session.distance * 70).round();

    final message =
        '''
🏃‍♂️ Моя пробежка в Ростове-на-Дону!

Дистанция: ${session.distance.toStringAsFixed(1)} км
Время: ${hours > 0 ? '$hoursч ' : ''}${minutes}м ${seconds}с
Темп: $paceMinutes:${paceSeconds.toString().padLeft(2, '0')} мин/км
Калории: $calories
Факты: ${session.factsCount}

#RunningHistorian #РостовНаДону #Бег
''';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Текст для шеринга скопирован: $message')),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить тренировку?'),
        content: const Text(
          'Вы уверены, что хотите удалить эту тренировку? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              // Логика удаления сессии
              Navigator.pop(context);
              Navigator.pop(context); // Вернуться к истории
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

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
          strokeWidth: 6,
          color: color,
        ),
      );
    }

    return polylines;
  }
}
