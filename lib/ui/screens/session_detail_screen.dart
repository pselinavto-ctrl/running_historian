import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart'; // ✅ ДОБАВЛЕН КРИТИЧЕСКИ ВАЖНЫЙ ИМПОРТ
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/landmark.dart'; // ✅ ДЛЯ Landmark
import 'package:running_historian/config/constants.dart';
import 'dart:math' as math;

class SessionDetailScreen extends StatelessWidget {
  final RunSession session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    // Рассчитаем границы маршрута для автоматического приближения карты
    final (LatLngBounds, double) mapFocus =
        _calculateMapBoundsAndZoom(session.route);
    final mapBounds = mapFocus.$1;
    final autoZoom = mapFocus.$2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали пробежки'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareResults(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. КАРТА (ПО ВЫСОТЕ БОЛЬШЕ И БЛИЖЕ!)
          Expanded(
            flex: 2, // Карта занимает больше места
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: FlutterMap(
                mapController: MapController(),
                options: MapOptions(
                  initialCenter: mapBounds.center,
                  initialZoom: autoZoom,
                  // Отключаем ненужную интерактивность для экрана деталей
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.running_historian',
                  ),
                  if (session.route.isNotEmpty)
                    PolylineLayer(
                      polylines: _buildSpeedPolylines(session.route),
                    ),
                  if (session.route.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(
                              session.route.first.lat, session.route.first.lon),
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.flag,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        Marker(
                          point: LatLng(
                              session.route.last.lat, session.route.last.lon),
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          // 2. СТАТИСТИКА (компактная и стильная)
          _buildCompactStatsPanel(),
          // 3. ДОСТОПРИМЕЧАТЕЛЬНОСТИ И ФАКТЫ
          if (session.spokenFactIndices.isNotEmpty ||
              _getNearbyLandmarks(session.route).isNotEmpty) ...[
            _buildPoiAndFactsSection(session),
            const SizedBox(height: 8),
          ],
          // 4. КНОПКИ ДЕЙСТВИЙ
          _buildActionButtons(context),
        ],
      ),
    );
  }

  // ========== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ==========

  // 1. Рассчёт границ маршрута и зума
  (LatLngBounds, double) _calculateMapBoundsAndZoom(List<RoutePoint> route) {
    if (route.isEmpty) {
      return (LatLngBounds(const LatLng(47.2313, 39.7233),
          const LatLng(47.2313, 39.7233)), 13.0);
    }

    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final point in route) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }

    final bounds =
        LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));

    // Автоматический расчёт зума на основе размера маршрута
    const double maxZoom = 17.0;
    const double minZoom = 11.0;
    const double maxDiagonalKm = 5.0; // Максимальный размер маршрута для приближения

    final diagonalDistance = Geolocator.distanceBetween(
          bounds.southWest.latitude,
          bounds.southWest.longitude,
          bounds.northEast.latitude,
          bounds.northEast.longitude,
        ) /
        1000; // в км

    double zoom = maxZoom;
    if (diagonalDistance > 0.1) {
      zoom = maxZoom - (math.log(diagonalDistance / maxDiagonalKm + 1) / math.ln2);
      zoom = zoom.clamp(minZoom, maxZoom);
    }

    return (bounds, zoom);
  }

  // 2. Компактная панель статистики
  Widget _buildCompactStatsPanel() {
    final duration = Duration(seconds: session.duration);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final pace =
        session.distance > 0 ? (session.duration / session.distance) : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();
    final calories = (session.distance * 70).round();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      color: Colors.grey[50],
      child: Column(
        children: [
          // Верхняя строка: Основные метрики
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactMetric(
                Icons.route,
                '${session.distance.toStringAsFixed(1)} км',
                'Дистанция',
                Colors.blue,
              ),
              _buildCompactMetric(
                Icons.timer,
                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                'Время',
                Colors.green,
              ),
              _buildCompactMetric(
                Icons.speed,
                '$paceMinutes:${paceSeconds.toString().padLeft(2, '0')}',
                'Темп',
                _getPaceColor(pace.toDouble()), // ✅ ДОБАВЛЕНО .toDouble()
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Нижняя строка: Дополнительные метрики
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactMetric(
                Icons.local_fire_department,
                '$calories',
                'Кал',
                Colors.orange,
              ),
              _buildCompactMetric(
                Icons.fact_check,
                '${session.factsCount}',
                'Фактов',
                Colors.purple,
              ),
              _buildCompactMetric(
                Icons.place,
                '${session.route.length}',
                'Точек',
                Colors.grey[700]!,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetric(
      IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // 3. Секция достопримечательностей и фактов
  Widget _buildPoiAndFactsSection(RunSession session) {
    final nearbyLandmarks = _getNearbyLandmarks(session.route);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nearbyLandmarks.isNotEmpty) ...[
            const Text('📍 Достопримечательности',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: nearbyLandmarks.map((landmark) {
                return Chip(
                  label: Text(landmark.name),
                  avatar: const Icon(Icons.location_pin, size: 16),
                  backgroundColor: Colors.red.withOpacity(0.1),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (session.spokenFactIndices.isNotEmpty) ...[
            const Text('📚 Интересные факты',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...session.spokenFactIndices.take(3).map((index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info, color: Colors.deepPurple, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kGeneralFacts[index],
                        style: TextStyle(color: Colors.grey[800]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  // 4. Метод для получения достопримечательностей рядом с маршрутом
  List<Landmark> _getNearbyLandmarks(List<RoutePoint> route) {
    const double proximityThreshold = 200.0; // метров
    final Set<Landmark> landmarksSet = {};

    for (final point in route) {
      for (final landmark in kLandmarks) {
        final distance = Geolocator.distanceBetween(
          point.lat,
          point.lon,
          landmark.lat,
          landmark.lon,
        );
        if (distance <= proximityThreshold) {
          landmarksSet.add(landmark);
        }
      }
    }
    return landmarksSet.toList();
  }

  // 5. Цвет темпа
  Color _getPaceColor(double paceSeconds) {
    if (paceSeconds < 300) return Colors.green; // <5 мин/км
    if (paceSeconds < 420) return Colors.orange; // <7 мин/км
    return Colors.red; // >7 мин/км
  }

  // 6. Кнопки действий
  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.replay, color: Colors.white),
            label: const Text('Повторить', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              minimumSize: const Size(150, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _showDeleteConfirmation(context),
            icon: const Icon(Icons.delete, color: Colors.white),
            label: const Text('Удалить', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              minimumSize: const Size(150, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // 7. Полилинии с градиентом скорости
  List<Polyline> _buildSpeedPolylines(List<RoutePoint> route) {
    final polylines = <Polyline>[];
    if (route.length < 2) return polylines;

    for (int i = 1; i < route.length; i++) {
      final p1 = route[i - 1];
      final p2 = route[i];

      Color color;
      if (p1.speed < 2) {
        color = Colors.blue;
      } else if (p1.speed < 5) {
        color = const Color(0xFF9C27B0);
      } else {
        color = Colors.red;
      }

      polylines.add(Polyline(
        points: [LatLng(p1.lat, p1.lon), LatLng(p2.lat, p2.lon)],
        strokeWidth: 5,
        color: color,
      ));
    }
    return polylines;
  }

  // 8. Шеринг и подтверждение удаления (остаются без изменений)
  void _shareResults(BuildContext context) {
    final duration = Duration(seconds: session.duration);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final pace = session.distance > 0 ? (session.duration / session.distance) : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();
    final calories = (session.distance * 70).round();

    final message =
        '''🏃‍♂️ Моя пробежка в Ростове-на-Дону!

Дистанция: ${session.distance.toStringAsFixed(1)} км
Время: ${hours > 0 ? '$hoursч ' : ''}${minutes}м ${seconds}с
Темп: $paceMinutes:${paceSeconds.toString().padLeft(2, '0')} мин/км
Калории: $calories
Факты: ${session.factsCount}

#RunningHistorian #РостовНаДону #Бег''';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Текст для шеринга скопирован: $message')),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить тренировку?'),
        content: const Text('Вы уверены? Это действие нельзя отменить.'),
        actions: [
          TextButton(
              onPressed: Navigator.of(context).pop, child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}