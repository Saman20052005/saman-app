/// Normalized 3D landmark corresponding to MediaPipe 33-point pose model.
class PoseLandmark {
  final int index;
  final double x; // [0.0, 1.0]
  final double y; // [0.0, 1.0]
  final double z;
  final double visibility; // [0.0, 1.0]

  const PoseLandmark({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  factory PoseLandmark.fromMap(Map<dynamic, dynamic> map) {
    return PoseLandmark(
      index: (map['index'] as num?)?.toInt() ?? 0,
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      z: (map['z'] as num?)?.toDouble() ?? 0.0,
      visibility: (map['visibility'] as num?)?.toDouble() ?? 0.0,
    );
  }

  bool isVisible({double threshold = 0.5}) => visibility >= threshold;

  // MediaPipe Landmark Indices
  static const int nose = 0;
  static const int leftEyeInner = 1;
  static const int leftEye = 2;
  static const int leftEyeOuter = 3;
  static const int rightEyeInner = 4;
  static const int rightEye = 5;
  static const int rightEyeOuter = 6;
  static const int leftEar = 7;
  static const int rightEar = 8;
  static const int mouthLeft = 9;
  static const int mouthRight = 10;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
  static const int leftPinky = 17;
  static const int rightPinky = 18;
  static const int leftIndex = 19;
  static const int rightIndex = 20;
  static const int leftThumb = 21;
  static const int rightThumb = 22;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;

  /// Standard connections for human body skeleton overlay
  static const List<List<int>> skeletonConnections = [
    // Torso & Shoulders
    [11, 12],
    [11, 23],
    [12, 24],
    [23, 24],
    // Left Arm
    [11, 13],
    [13, 15],
    // Right Arm
    [12, 14],
    [14, 16],
    // Left Leg
    [23, 25],
    [25, 27],
    // Right Leg
    [24, 26],
    [26, 28],
  ];

  /// Key upper body joints required for Pull-up and Lat Pulldown tracking
  static const List<int> upperBodyKeyJoints = [
    leftShoulder,
    rightShoulder,
    leftElbow,
    rightElbow,
    leftWrist,
    rightWrist,
    leftHip,
    rightHip,
  ];
}
