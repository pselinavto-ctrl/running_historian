import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/domain/route_point.dart';
import 'package:running_historian/domain/landmark.dart';
import 'package:running_historian/config/constants.dart';
import 'package:running_historian/storage/run_repository.dart';
import 'dart:math' as math;

class SessionDetailScreen extends StatelessWidget {
  final RunSession session;

  const SessionDetailScreen({super.key, required this.session});

  static const Color _backgroundColor = Color(0xFF0A0A0A);
  static const Color _surfaceColor = Color(0xFF1A1A1A);
  static const Color _primaryColor = Color(0xFF00FF9D);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFFA0A0A0);
  static const Color _dividerColor = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    final (LatLngBounds, double) mapFocus = _calculateMapBoundsAndZoom(session.route);
    final mapBounds = mapFocus.$1;
    final autoZoom = mapFocus.$2;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('Детали пробежки', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w300, letterSpacing: 0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, size: 22),
            onPressed: () => _shareResults(context),
            color: _textSecondary,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: FlutterMap(
                mapController: MapController(),
                options: MapOptions(
                  initialCenter: mapBounds.center,
                  initialZoom: autoZoom,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.running_historian',
                  ),
                  if (session.route.isNotEmpty)
                    PolylineLayer(polylines: _buildMinimalPolylines(session.route)),
                  if (session.route.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(session.route.first.lat, session.route.first.lon),
                          width: 32,
                          height: 32,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)],
                            ),
                            child: const Icon(Icons.flag, color: _backgroundColor, size: 16),
                          ),
                        ),
                        Marker(
                          point: LatLng(session.route.last.lat, session.route.last.lon),
                          width: 32,
                          height: 32,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _textPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(color: _primaryColor, width: 2),
                            ),
                            child: const Icon(Icons.circle, color: _primaryColor, size: 12),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          _buildMinimalStatsPanel(),
          if (session.spokenFactIndices.isNotEmpty || _getNearbyLandmarks(session.route).isNotEmpty)
            _buildMinimalPoiSection(session),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.replay, size: 20),
                    label: const Text('Повторить маршрут', style: TextStyle(fontWeight: FontWeight.w500)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: _primaryColor, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showDeleteConfirmation(context),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: const Text('Удалить', style: TextStyle(fontWeight: FontWeight.w500)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.withOpacity(0.9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (LatLngBounds, double) _calculateMapBoundsAndZoom(List<RoutePoint> route) {
    if (route.isEmpty) {
      return (LatLngBounds(const LatLng(47.2313, 39.7233), const LatLng(47.2313, 39.7233)), 13.0);
    }
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final point in route) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }
    final bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
    const double maxZoom = 17.0;
    const double minZoom = 11.0;
    const double maxDiagonalKm = 5.0;
    final diagonalDistance = Geolocator.distanceBetween(bounds.southWest.latitude, bounds.southWest.longitude, bounds.northEast.latitude, bounds.northEast.longitude) / 1000;
    double zoom = maxZoom;
    if (diagonalDistance > 0.1) {
      zoom = maxZoom - (math.log(diagonalDistance / maxDiagonalKm + 1) / math.ln2);
      zoom = zoom.clamp(minZoom, maxZoom);
    }
    return (bounds, zoom);
  }

  Widget _buildMinimalStatsPanel() {
    final duration = Duration(seconds: session.duration);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final pace = session.distance > 0 ? (session.duration / session.distance) : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();
    final calories = (session.distance * 70).round();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Дистанция', style: TextStyle(fontSize: 14, color: _textSecondary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('${session.distance.toStringAsFixed(2)} км', style: const TextStyle(fontSize: 32, color: _textPrimary, fontWeight: FontWeight.w300)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Время', style: TextStyle(fontSize: 14, color: _textSecondary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 32, color: _textPrimary, fontWeight: FontWeight.w300)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _dividerColor, width: 1), bottom: BorderSide(color: _dividerColor, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMinimalMetric(Icons.speed, 'Темп', '$paceMinutes:${paceSeconds.toString().padLeft(2, '0')}'),
                Container(width: 1, height: 40, color: _dividerColor),
                _buildMinimalMetric(Icons.local_fire_department, 'Калории', '$calories'),
                Container(width: 1, height: 40, color: _dividerColor),
                _buildMinimalMetric(Icons.menu_book, 'Фактов', session.spokenFactIndices.length.toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalMetric(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: _textSecondary, size: 20),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, color: _textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, color: _textPrimary, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildMinimalPoiSection(RunSession session) {
    final nearbyLandmarks = _getNearbyLandmarks(session.route);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: _surfaceColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nearbyLandmarks.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.place, color: _primaryColor, size: 18),
                const SizedBox(width: 8),
                Text('Вы прошли рядом', style: TextStyle(fontSize: 16, color: _textPrimary, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: nearbyLandmarks.map((landmark) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _backgroundColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _dividerColor, width: 1),
                    ),
                    child: Text(landmark.name, style: const TextStyle(color: _textPrimary)),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (session.spokenFactIndices.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: _primaryColor, size: 18),
                const SizedBox(width: 8),
                Text('Интересные факты (${session.spokenFactIndices.length})', style: TextStyle(fontSize: 16, color: _textPrimary, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 12),
            ...session.spokenFactIndices.map((index) {
              String factText = (index >= 0 && index < kGeneralFacts.length) ? kGeneralFacts[index] : "Интересный факт #$index";
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(margin: const EdgeInsets.only(top: 4), width: 6, height: 6, decoration: BoxDecoration(color: _primaryColor, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(factText, style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.4))),
                  ],
                ),
              );
            }).toList(),
          ],
        ],
      ),
    );
  }

  List<Landmark> _getNearbyLandmarks(List<RoutePoint> route) {
    const double proximityThreshold = 200.0;
    final Set<Landmark> landmarksSet = {};
    for (final point in route) {
      for (final landmark in kLandmarks) {
        final distance = Geolocator.distanceBetween(point.lat, point.lon, landmark.lat, landmark.lon);
        if (distance <= proximityThreshold) {
          landmarksSet.add(landmark);
        }
      }
    }
    return landmarksSet.toList();
  }

  List<Polyline> _buildMinimalPolylines(List<RoutePoint> route) {
    final polylines = <Polyline>[];
    if (route.length < 2) return polylines;
    for (int i = 1; i < route.length; i++) {
      final p1 = route[i - 1];
      final p2 = route[i];
      double opacity = p1.speed < 2 ? 0.4 : p1.speed < 5 ? 0.7 : 1.0;
      polylines.add(Polyline(points: [LatLng(p1.lat, p1.lon), LatLng(p2.lat, p2.lon)], strokeWidth: 4.5, color: _primaryColor.withOpacity(opacity)));
    }
    return polylines;
  }

  void _shareResults(BuildContext context) {
    final duration = Duration(seconds: session.duration);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final pace = session.distance > 0 ? (session.duration / session.distance) : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();
    final calories = (session.distance * 70).round();

    final message = '''🏃‍♂️ Моя пробежка в Ростове-на-Дону!

Дистанция: ${session.distance.toStringAsFixed(1)} км
Время: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}
Темп: $paceMinutes:${paceSeconds.toString().padLeft(2, '0')} мин/км
Калории: $calories
Факты: ${session.spokenFactIndices.length}

#RunningHistorian #РостовНаДону''';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _surfaceColor,
        content: Text('Текст скопирован', style: TextStyle(color: _primaryColor)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text('Удалить тренировку?', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Text('Это действие нельзя отменить.', style: TextStyle(fontSize: 14, color: _textSecondary)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: Navigator.of(context).pop,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textPrimary,
                        side: BorderSide(color: _dividerColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await RunRepository().deleteSession(session.id);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Удалить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}