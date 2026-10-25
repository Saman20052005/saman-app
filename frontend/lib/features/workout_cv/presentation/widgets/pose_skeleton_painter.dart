import 'package:flutter/material.dart';
import '../../domain/entities/exercise_cv_state.dart';
import '../../domain/entities/pose_landmark.dart';

class PoseSkeletonPainter extends CustomPainter {
  final List<PoseLandmark> landmarks;
  final TrackingStatus trackingStatus;
  final bool isSyncValid;

  PoseSkeletonPainter({
    required this.landmarks,
    required this.trackingStatus,
    this.isSyncValid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw subtle framing guide box to assist positioning
    _drawFramingGuide(canvas, size);

    if (!isSyncValid || landmarks.isEmpty ||
        trackingStatus == TrackingStatus.lost ||
        trackingStatus == TrackingStatus.multiplePeople) {
      return;
    }

    final isConfident = trackingStatus == TrackingStatus.detecting;
    final lineColor = isConfident
        ? const Color(0xFF10B981) // Emerald
        : const Color(0xFFF59E0B); // Amber
    final jointColor = isConfident
        ? const Color(0xFF34D399) // Bright Emerald
        : const Color(0xFFFBBF24); // Bright Amber

    final linePaint = Paint()
      ..color = lineColor.withOpacity(0.85)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = jointColor
      ..style = PaintingStyle.fill;

    final outerJointPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 2. Draw Connections
    for (final connection in PoseLandmark.skeletonConnections) {
      final startIndex = connection[0];
      final endIndex = connection[1];

      if (startIndex < landmarks.length && endIndex < landmarks.length) {
        final start = landmarks[startIndex];
        final end = landmarks[endIndex];

        // Only draw if both joints have reasonable visibility
        if (start.isVisible(threshold: 0.4) && end.isVisible(threshold: 0.4)) {
          final p1 = Offset(start.x * size.width, start.y * size.height);
          final p2 = Offset(end.x * size.width, end.y * size.height);
          canvas.drawLine(p1, p2, linePaint);
        }
      }
    }

    // 3. Draw Landmark Joints
    for (final lm in landmarks) {
      if (!lm.isVisible(threshold: 0.4)) continue;

      final point = Offset(lm.x * size.width, lm.y * size.height);
      // Key upper body joints get larger dots
      final isKeyJoint = PoseLandmark.upperBodyKeyJoints.contains(lm.index);
      final radius = isKeyJoint ? 5.5 : 3.5;

      canvas.drawCircle(point, radius, jointPaint);
      canvas.drawCircle(point, radius, outerJointPaint);
    }
  }

  void _drawFramingGuide(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const marginX = 24.0;
    const marginTop = 48.0;
    const marginBottom = 80.0;
    final rect = Rect.fromLTWH(
      marginX,
      marginTop,
      size.width - (marginX * 2),
      size.height - marginTop - marginBottom,
    );

    // Subtle corner brackets
    const cornerLength = 24.0;
    // Top-Left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cornerLength, 0), guidePaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cornerLength), guidePaint);
    // Top-Right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cornerLength, 0), guidePaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cornerLength), guidePaint);
    // Bottom-Left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cornerLength, 0), guidePaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLength), guidePaint);
    // Bottom-Right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cornerLength, 0), guidePaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLength), guidePaint);
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) {
    return oldDelegate.isSyncValid != isSyncValid || oldDelegate.landmarks != landmarks || oldDelegate.trackingStatus != trackingStatus;
  }
}
