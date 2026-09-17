import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool isLightMode;

  const AppLogo({
    super.key,
    this.size = 100,
    this.color,
    this.isLightMode = true,
  });

  @override
  Widget build(BuildContext context) {
    // Màu chủ đạo: Nếu Light Mode dùng màu Đen Than (0xFF1E1E1E), Dark Mode dùng Trắng
    final primaryColor =
        color ?? (isLightMode ? const Color(0xFF1E1E1E) : Colors.white);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SamanLogoPainter(color: primaryColor),
      ),
    );
  }
}

class _SamanLogoPainter extends CustomPainter {
  final Color color;

  _SamanLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Paint style
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke // Vẽ nét (không tô đặc)
      ..strokeWidth = w * 0.15 // Nét dày khỏe khoắn
      ..strokeCap = StrokeCap.round // Đầu nét bo tròn
      ..isAntiAlias = true;

    // Vẽ hình chữ S cách điệu
    final path = Path();

    // Bắt đầu từ phải, cong xuống giữa
    path.moveTo(w * 0.8, h * 0.25);
    path.cubicTo(
        w * 0.2,
        h * 0.25, // Điểm điều hướng 1
        w * 0.8,
        h * 0.75, // Điểm điều hướng 2
        w * 0.2,
        h * 0.75 // Điểm cuối
        );

    // Vẽ nền tròn mờ nhẹ phía sau (Option)
    final bgPaint = Paint()
      ..color = color.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.6, bgPaint);

    // Vẽ biểu tượng chính
    canvas.drawPath(path, paint);

    // Vẽ chấm tròn nhỏ
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(w * 0.8, h * 0.25), w * 0.08, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
