import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The VoxelOps mark: an isometric voxel cube with rack slots and a live LED.
/// Geometry matches tool/generate_icons.py so the launcher icon and the in-app logo agree.
class VoxelLogo extends StatefulWidget {
  const VoxelLogo({super.key, this.size = 96, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<VoxelLogo> createState() => _VoxelLogoState();
}

class _VoxelLogoState extends State<VoxelLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VoxelLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CubePainter(progress: _controller.value),
      ),
    );
  }
}

class _CubePainter extends CustomPainter {
  _CubePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final edge = s * 0.36;
    final a = edge * 0.866;
    final b = edge * 0.5;
    final lift = math.sin(progress * math.pi * 2) * s * 0.012;
    final origin = Offset(s / 2, s / 2 + lift);

    final top = <Offset>[origin, origin + Offset(-a, -b), origin + Offset(0, -edge), origin + Offset(a, -b)];
    final left = <Offset>[origin, origin + Offset(-a, -b), origin + Offset(-a, b), origin + Offset(0, edge)];
    final right = <Offset>[origin, origin + Offset(a, -b), origin + Offset(a, b), origin + Offset(0, edge)];

    _fill(canvas, top, const [Color(0xFF9DC4FF), Color(0xFF548EFF)]);
    _fill(canvas, left, const [Color(0xFF4680FF), Color(0xFF4C3CDE)]);
    _fill(canvas, right, const [Color(0xFF7846F0), Color(0xFF9664FA)]);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = math.max(1.0, s * 0.0035)
      ..style = PaintingStyle.stroke;
    _grid(canvas, top, grid);
    _grid(canvas, left, grid);
    _grid(canvas, right, grid);

    final slotPaint = Paint()..color = const Color(0xFF14103C).withValues(alpha: 0.6);
    final leds = <Color>[AppColors.success, AppColors.success, AppColors.cyan];
    for (var i = 0; i < 3; i++) {
      final v0 = 0.22 + i * 0.22;
      final v1 = v0 + 0.13;
      final slot = Path()
        ..addPolygon(<Offset>[_map(right, 0.18, v0), _map(right, 0.82, v0), _map(right, 0.82, v1), _map(right, 0.18, v1)], true);
      canvas.drawPath(slot, slotPaint);
      final led = _map(right, 0.27, (v0 + v1) / 2);
      final pulse = 0.5 + 0.5 * math.sin((progress * 2 * math.pi) + i * 1.1);
      canvas.drawCircle(led, s * 0.03 * (1 + pulse * 0.25), Paint()..color = leds[i].withValues(alpha: 0.25));
      canvas.drawCircle(led, s * 0.013, Paint()..color = leds[i]);
    }
  }

  /// Maps (u, v) on a face whose corners are [origin, origin+u, origin+u+v, origin+v].
  static Offset _map(List<Offset> face, double u, double v) {
    final origin = face[0];
    final uVec = face[1] - origin;
    final vVec = face[3] - origin;
    return origin + uVec * u + vVec * v;
  }

  static void _grid(Canvas canvas, List<Offset> face, Paint paint) {
    for (final k in <double>[1 / 3, 2 / 3]) {
      canvas.drawLine(_map(face, k, 0), _map(face, k, 1), paint);
      canvas.drawLine(_map(face, 0, k), _map(face, 1, k), paint);
    }
  }

  void _fill(Canvas canvas, List<Offset> points, List<Color> colors) {
    final path = Path()..addPolygon(points, true);
    final rect = path.getBounds();
    final paint = Paint()
      ..shader = LinearGradient(colors: colors, begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CubePainter oldDelegate) => oldDelegate.progress != progress;
}
