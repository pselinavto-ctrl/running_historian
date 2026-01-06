import 'package:flutter/material.dart';

class CompassMarker extends StatelessWidget {
  final double rotation;
  final double size;

  const CompassMarker({
    super.key,
    required this.rotation,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation * (3.141592653589793 / 180), // Градусы → радианы
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        child: CustomPaint(
          size: Size(size, size),
          painter: CompassPainter(rotation: rotation),
        ),
      ),
    );
  }
}

class CompassPainter extends CustomPainter {
  final double rotation;

  CompassPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFFFFD700) // Золотой цвет
      ..style = PaintingStyle.fill;

    // Рисуем стрелку
    final path = Path()
      ..moveTo(center.dx, center.dy - size.width / 2 + 5)
      ..lineTo(center.dx - size.width / 4, center.dy + size.width / 4 - 5)
      ..lineTo(center.dx, center.dy + size.width / 4)
      ..lineTo(center.dx + size.width / 4, center.dy + size.width / 4 - 5)
      ..close();

    canvas.drawPath(path, paint);

    // Добавляем тень
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      path.shift(Offset(2, 2)),
      shadowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}