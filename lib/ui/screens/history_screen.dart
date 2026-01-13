import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:running_historian/domain/run_session.dart';
import 'package:running_historian/ui/screens/session_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  final List<RunSession> history;

  const HistoryScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История пробежек'),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
        elevation: 0,
      ),
      body: history.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final session = history[index];
                // ПРОСТАЯ АНИМАЦИЯ БЕЗ СЛОЖНОЙ ЦЕПОЧКИ
                return _buildSessionCard(session, context)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (100 * index).ms);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.deepPurple.withOpacity(0.6),
          ),
          const SizedBox(height: 24),
          Text(
            'Пока нет пробежек',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text(
            'Начните первую тренировку,\nчтобы увидеть историю здесь',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }

  Widget _buildSessionCard(RunSession session, BuildContext context) {
    final date = session.date;
    final formattedDate = '${date.day}.${date.month}.${date.year}';
    final formattedTime = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final duration = Duration(seconds: session.duration);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final pace = session.distance > 0 ? (session.duration / session.distance) : 0;
    final paceMinutes = (pace / 60).floor();
    final paceSeconds = (pace % 60).round();

    Color getPaceColor() {
      if (pace < 300) return Colors.green;
      if (pace < 420) return Colors.orange;
      return Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SessionDetailScreen(session: session),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.deepPurple.withOpacity(0.1),
        highlightColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18, color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
                    ),
                    child: Text(
                      formattedTime,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricTile(
                    icon: Icons.route,
                    value: '${session.distance.toStringAsFixed(1)} км',
                    label: 'Дистанция',
                    color: Colors.blue,
                  ),
                  _buildMetricTile(
                    icon: Icons.timer,
                    value: '$minutes:${seconds.toString().padLeft(2, '0')}',
                    label: 'Время',
                    color: Colors.green,
                  ),
                  _buildMetricTile(
                    icon: Icons.speed,
                    value: '$paceMinutes:${paceSeconds.toString().padLeft(2, '0')}',
                    label: 'Темп',
                    color: getPaceColor(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (session.route.isNotEmpty && session.route.length > 1) ...[
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      options: MapOptions(
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                        initialCenter: LatLng(
                          session.route.first.lat,
                          session.route.first.lon,
                        ),
                        initialZoom: 13.5,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.running_historian',
                        ),
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: session.route
                                  .map((p) => LatLng(p.lat, p.lon))
                                  .toList(),
                              color: Colors.deepPurple.withOpacity(0.7),
                              strokeWidth: 3,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book, size: 18, color: Colors.purple[600]),
                      const SizedBox(width: 6),
                      Text(
                        '${session.factsCount} фактов',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Text(
                          'Подробнее',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.deepPurple,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 10, color: Colors.deepPurple),
                      ],
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

  Widget _buildMetricTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}