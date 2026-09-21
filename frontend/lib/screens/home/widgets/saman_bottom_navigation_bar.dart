import 'package:flutter/material.dart';
import '../tokens/saman_home_tokens.dart';

/// The approved Saman 5-tab bottom navigation bar matching the Obsidian design handoff:
/// - Home (house icon)
/// - Workout (barbell icon)
/// - Saman (minimal custom uppercase S monogram)
/// - Nutrition (fork & knife icon)
/// - Profile (person outline icon)
///
/// Features:
/// - Active item: white icon + white text + tiny 4x4 white dot underneath
/// - Inactive items: muted gray icon + text + transparent dot (for fixed height stability)
/// - Background: obsidian dark (#0C0D0E) with subtle graphite top divider (#23252A)
/// - Safe area aware with minimum bottom breathing room
class SamanBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SamanBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final effectiveBottom = bottomInset > 0 ? bottomInset : 12.0;

    return Container(
      decoration: const BoxDecoration(
        color: SamanHomeTokens.canvas,
        border: Border(
          top: BorderSide(
            color: SamanHomeTokens.borderSubtle,
            width: 1.0,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: 8.0,
        bottom: effectiveBottom,
        left: 4.0,
        right: 4.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, 'Home', const _HomeIconPainter()),
          _buildNavItem(1, 'Workout', const _WorkoutIconPainter()),
          _buildNavItem(2, 'Saman', const _SamanIconPainter()),
          _buildNavItem(3, 'Nutrition', const _NutritionIconPainter()),
          _buildNavItem(4, 'Profile', const _ProfileIconPainter()),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, _IconPainter painter) {
    final isSelected = currentIndex == index;
    const activeColor = SamanHomeTokens.textWhite;
    const inactiveColor = Color(0xFF9CA3AF);
    final color = isSelected ? activeColor : inactiveColor;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: () => onTap(index),
            radius: 28,
            containedInkWell: false,
            highlightColor: Colors.transparent,
            splashColor: Colors.white.withOpacity(0.08),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(
                    painter: _DelegatePainter(painter, color),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? SamanHomeTokens.textWhite : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

abstract class _IconPainter {
  void paint(Canvas canvas, Size size, Color color);
}

class _DelegatePainter extends CustomPainter {
  final _IconPainter painter;
  final Color color;

  _DelegatePainter(this.painter, this.color);

  @override
  void paint(Canvas canvas, Size size) => painter.paint(canvas, size, color);

  @override
  bool shouldRepaint(covariant _DelegatePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.painter != painter;
}

class _HomeIconPainter implements _IconPainter {
  const _HomeIconPainter();

  @override
  void paint(Canvas canvas, Size size, Color color) {
    final s = size.width / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(3 * s, 10.5 * s)
      ..lineTo(12 * s, 3.5 * s)
      ..lineTo(21 * s, 10.5 * s)
      ..lineTo(21 * s, 20 * s)
      ..arcToPoint(Offset(20 * s, 21 * s), radius: Radius.circular(1 * s))
      ..lineTo(15 * s, 21 * s)
      ..lineTo(15 * s, 15 * s)
      ..lineTo(9 * s, 15 * s)
      ..lineTo(9 * s, 21 * s)
      ..lineTo(4 * s, 21 * s)
      ..arcToPoint(Offset(3 * s, 20 * s), radius: Radius.circular(1 * s))
      ..close();

    canvas.drawPath(path, paint);
  }
}

class _WorkoutIconPainter implements _IconPainter {
  const _WorkoutIconPainter();

  @override
  void paint(Canvas canvas, Size size, Color color) {
    final s = size.width / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Center bar
      ..moveTo(6 * s, 12 * s)
      ..lineTo(18 * s, 12 * s)
      // Inner plates
      ..moveTo(6 * s, 5 * s)
      ..lineTo(6 * s, 19 * s)
      ..moveTo(18 * s, 5 * s)
      ..lineTo(18 * s, 19 * s)
      // Outer collars
      ..moveTo(2 * s, 9 * s)
      ..lineTo(2 * s, 15 * s)
      ..moveTo(22 * s, 9 * s)
      ..lineTo(22 * s, 15 * s);

    canvas.drawPath(path, paint);
  }
}

class _SamanIconPainter implements _IconPainter {
  const _SamanIconPainter();

  @override
  void paint(Canvas canvas, Size size, Color color) {
    final s = size.width / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Upper curve: M17.5 7.5A4.5 4.5 0 0 0 8 6c-3 1.8-3.5 5-1 7.2l2.5 1.8
      ..moveTo(17.5 * s, 7.5 * s)
      ..arcToPoint(
        Offset(8 * s, 6 * s),
        radius: Radius.circular(4.5 * s),
        clockwise: false,
      )
      ..cubicTo(
        5 * s,
        7.8 * s,
        4.5 * s,
        11 * s,
        7 * s,
        13.2 * s,
      )
      ..lineTo(9.5 * s, 15 * s)
      // Lower curve: M6.5 16.5A4.5 4.5 0 0 0 16 18c3-1.8 3.5-5 1-7.2l-2.5-1.8
      ..moveTo(6.5 * s, 16.5 * s)
      ..arcToPoint(
        Offset(16 * s, 18 * s),
        radius: Radius.circular(4.5 * s),
        clockwise: false,
      )
      ..cubicTo(
        19 * s,
        16.2 * s,
        19.5 * s,
        13 * s,
        17 * s,
        10.8 * s,
      )
      ..lineTo(14.5 * s, 9 * s);

    canvas.drawPath(path, paint);
  }
}

class _NutritionIconPainter implements _IconPainter {
  const _NutritionIconPainter();

  @override
  void paint(Canvas canvas, Size size, Color color) {
    final s = size.width / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      // Right utensil (knife/spoon): M18 3v5a3 3 0 01-3 3h-1m4-8h-4m4 0v18
      ..moveTo(18 * s, 3 * s)
      ..lineTo(18 * s, 8 * s)
      ..arcToPoint(
        Offset(15 * s, 11 * s),
        radius: Radius.circular(3 * s),
        clockwise: true,
      )
      ..lineTo(14 * s, 11 * s)
      ..moveTo(18 * s, 3 * s)
      ..lineTo(14 * s, 3 * s)
      ..moveTo(18 * s, 3 * s)
      ..lineTo(18 * s, 21 * s)
      // Left utensil (fork): M6 3v6a2.5 2.5 0 005 0V3M8.5 11.5V21
      ..moveTo(6 * s, 3 * s)
      ..lineTo(6 * s, 9 * s)
      ..arcToPoint(
        Offset(11 * s, 9 * s),
        radius: Radius.circular(2.5 * s),
        clockwise: true,
      )
      ..lineTo(11 * s, 3 * s)
      ..moveTo(8.5 * s, 11.5 * s)
      ..lineTo(8.5 * s, 21 * s);

    canvas.drawPath(path, paint);
  }
}

class _ProfileIconPainter implements _IconPainter {
  const _ProfileIconPainter();

  @override
  void paint(Canvas canvas, Size size, Color color) {
    final s = size.width / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Head circle: cx="12" cy="7" r="4"
    canvas.drawCircle(Offset(12 * s, 7 * s), 4 * s, paint);

    // Torso arc: M5.5 20.5a6.5 6.5 0 0113 0
    final path = Path()
      ..moveTo(5.5 * s, 20.5 * s)
      ..arcToPoint(
        Offset(18.5 * s, 20.5 * s),
        radius: Radius.circular(6.5 * s),
        clockwise: false,
      );

    canvas.drawPath(path, paint);
  }
}
