import 'package:flutter/foundation.dart';
import 'workout_cv_exercise_registry.dart';

/// How well a camera viewing angle is supported by 2D pose tracking.
enum CvAngleSupportLevel {
  best,
  supported,
  notRecommended,
}

/// Camera viewing angle option with localized label, support level, and note.
@immutable
class CvAngleOption {
  const CvAngleOption({
    required this.angleCode,
    required this.labelVi,
    required this.labelEn,
    required this.supportLevel,
    required this.noteVi,
    required this.noteEn,
  });

  final String angleCode;
  final String labelVi;
  final String labelEn;
  final CvAngleSupportLevel supportLevel;
  final String noteVi;
  final String noteEn;

  String label(bool isVietnamese) => isVietnamese ? labelVi : labelEn;
  String note(bool isVietnamese) => isVietnamese ? noteVi : noteEn;
}

/// Camera setup, supported angles, and honest 2D AI blind spots for an exercise.
@immutable
class CvExerciseGuideSpec {
  const CvExerciseGuideSpec({
    required this.module,
    required this.titleVi,
    required this.titleEn,
    required this.supportedAngles,
    required this.bestAngleSummaryVi,
    required this.bestAngleSummaryEn,
    this.angleWarningVi,
    this.angleWarningEn,
    required this.cameraPlacementVi,
    required this.cameraPlacementEn,
    required this.lightingTipVi,
    required this.lightingTipEn,
    required this.blindSpotsVi,
    required this.blindSpotsEn,
  });

  final CvExerciseModule? module;
  final String titleVi;
  final String titleEn;
  final List<CvAngleOption> supportedAngles;
  final String bestAngleSummaryVi;
  final String bestAngleSummaryEn;
  final String? angleWarningVi;
  final String? angleWarningEn;
  final String cameraPlacementVi;
  final String cameraPlacementEn;
  final String lightingTipVi;
  final String lightingTipEn;
  final List<String> blindSpotsVi;
  final List<String> blindSpotsEn;

  String title(bool isVietnamese) => isVietnamese ? titleVi : titleEn;

  String bestAngleSummary(bool isVietnamese) =>
      isVietnamese ? bestAngleSummaryVi : bestAngleSummaryEn;

  String? angleWarning(bool isVietnamese) =>
      isVietnamese ? angleWarningVi : angleWarningEn;

  String cameraPlacement(bool isVietnamese) =>
      isVietnamese ? cameraPlacementVi : cameraPlacementEn;

  String lightingTip(bool isVietnamese) =>
      isVietnamese ? lightingTipVi : lightingTipEn;

  List<String> blindSpots(bool isVietnamese) =>
      isVietnamese ? blindSpotsVi : blindSpotsEn;
}

/// Static catalog of camera setup guides and honest 2D AI blind spots.
class CvExerciseGuideData {
  const CvExerciseGuideData._();

  /// Returns the guide specification for an exercise resolved by [module],
  /// [slug], or [id], falling back to a general CV guide for other modules.
  static CvExerciseGuideSpec forExercise({
    String id = '',
    String slug = '',
    CvExerciseModule? module,
  }) {
    final resolved = module ??
        WorkoutCvExerciseRegistry.resolveModule(id: id, slug: slug);

    switch (resolved) {
      case CvExerciseModule.pullUp:
        return _pullUpSpec;
      case CvExerciseModule.latPulldown:
        return _latPulldownSpec;
      case CvExerciseModule.squat:
        return _squatSpec;
      case CvExerciseModule.pushUp:
        return _pushUpSpec;
      case CvExerciseModule.bicepCurl:
        return _bicepCurlSpec;
      case CvExerciseModule.row:
        return _fallbackSpec(
          module: CvExerciseModule.row,
          titleVi: 'Kéo lưng (Row)',
          titleEn: 'Row',
        );
      case CvExerciseModule.overheadPress:
        return _fallbackSpec(
          module: CvExerciseModule.overheadPress,
          titleVi: 'Đẩy vai (Overhead Press)',
          titleEn: 'Overhead Press',
        );
      case CvExerciseModule.plankHold:
        return _fallbackSpec(
          module: CvExerciseModule.plankHold,
          titleVi: 'Giữ Plank (Plank Hold)',
          titleEn: 'Plank Hold',
        );
      case CvExerciseModule.hipHinge:
        return _fallbackSpec(
          module: CvExerciseModule.hipHinge,
          titleVi: 'Gập hông (Hip Hinge)',
          titleEn: 'Hip Hinge',
        );
      case CvExerciseModule.hipThrust:
        return _fallbackSpec(
          module: CvExerciseModule.hipThrust,
          titleVi: 'Đẩy hông (Hip Thrust)',
          titleEn: 'Hip Thrust',
        );
      case CvExerciseModule.tricepExtension:
        return _fallbackSpec(
          module: CvExerciseModule.tricepExtension,
          titleVi: 'Tay sau (Tricep Extension)',
          titleEn: 'Tricep Extension',
        );
      case CvExerciseModule.lateralRaise:
        return _fallbackSpec(
          module: CvExerciseModule.lateralRaise,
          titleVi: 'Nâng vai ngang (Lateral Raise)',
          titleEn: 'Lateral Raise',
        );
      case CvExerciseModule.legExtension:
        return _fallbackSpec(
          module: CvExerciseModule.legExtension,
          titleVi: 'Đá đùi / Đạp chân',
          titleEn: 'Leg Extension / Press',
        );
      case CvExerciseModule.legCurl:
        return _fallbackSpec(
          module: CvExerciseModule.legCurl,
          titleVi: 'Cuốn đùi sau / Lunge',
          titleEn: 'Leg Curl / Lunge',
        );
      case CvExerciseModule.facePull:
        return _fallbackSpec(
          module: CvExerciseModule.facePull,
          titleVi: 'Kéo mặt (Face Pull)',
          titleEn: 'Face Pull',
        );
      case null:
        return _fallbackSpec(
          module: null,
          titleVi: 'Bài tập AI Camera',
          titleEn: 'AI Camera Exercise',
        );
    }
  }

  static const CvExerciseGuideSpec _pullUpSpec = CvExerciseGuideSpec(
    module: CvExerciseModule.pullUp,
    titleVi: 'Hít xà đơn (Pull-up)',
    titleEn: 'Pull-up',
    supportedAngles: [
      CvAngleOption(
        angleCode: '30–45°',
        labelVi: 'Chếch 30–45° (Tối ưu)',
        labelEn: '30–45° Angled (Best)',
        supportLevel: CvAngleSupportLevel.best,
        noteVi: 'Thấy rõ cả biên độ cùi chỏ, vai và độ cao cằm qua xà.',
        noteEn: 'Clearly captures elbow flexion, shoulders, and chin height.',
      ),
      CvAngleOption(
        angleCode: '0°/180°',
        labelVi: 'Chính diện / Sau 0°/180°',
        labelEn: 'Front / Back 0°/180°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Theo dõi tốt độ cân xứng hai vai và độ mở tay cầm.',
        noteEn: 'Good for tracking shoulder symmetry and grip width.',
      ),
      CvAngleOption(
        angleCode: '90°',
        labelVi: 'Ngang 90°',
        labelEn: 'Side 90°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Đo được độ ngả thân và vị trí cằm, dễ bị trụ xà che một bên tay.',
        noteEn: 'Tracks torso lean, though the rig upright may hide the far arm.',
      ),
    ],
    bestAngleSummaryVi:
        'Đặt máy chếch 30–45° phía trước hoặc sau để lấy rõ hai tay, vai và đường xà.',
    bestAngleSummaryEn:
        'Place the camera at a 30–45° angle to capture both arms, shoulders, and the bar.',
    cameraPlacementVi:
        'Đặt máy cao ngang ngực (cách 2–2.5 m), lấy trọn từ thanh xà/cổ tay đến hông suốt cả lúc duỗi thẳng tay lẫn khi kéo lên đỉnh.',
    cameraPlacementEn:
        'Set the camera at chest height (2–2.5 m away), framing from the bar and wrists down to your hips at both hang and peak.',
    lightingTipVi:
        'Tránh đặt máy hướng thẳng ra cửa sổ hoặc đèn trần chiếu gắt phía sau thanh xà gây tối silhouette.',
    lightingTipEn:
        'Avoid pointing the camera toward bright windows or overhead spotlights behind the bar.',
    blindSpotsVi: [
      'Thanh xà hoặc khung rack có thể che khuất mặt và cổ tay ở điểm kéo cao nhất.',
      'Áo khoác rộng hoặc áo hoodie dày làm AI 2D khó nhận đúng khớp vai và cùi chỏ.',
      'Lấy đà (kipping) hoặc giật người quá nhanh trên máy < 8 FPS dễ làm trễ hoặc mất đếm rep.',
      'Người đi ngang qua khung hình hoặc tay bị cắt sát rìa trên khung hình sẽ làm gián đoạn tracking.',
    ],
    blindSpotsEn: [
      'The pull-up bar or rack frame can occlude your face and wrists at the top of the rep.',
      'Baggy jackets or thick hoodies hide true shoulder and elbow joint positions in 2D.',
      'Fast kipping or swinging on devices running below 8 FPS can cause missed or delayed reps.',
      'Someone walking across the frame or hands clipping the top edge will interrupt tracking.',
    ],
  );

  static const CvExerciseGuideSpec _latPulldownSpec = CvExerciseGuideSpec(
    module: CvExerciseModule.latPulldown,
    titleVi: 'Kéo xô máy (Lat Pulldown)',
    titleEn: 'Lat Pulldown',
    supportedAngles: [
      CvAngleOption(
        angleCode: '30–45°',
        labelVi: 'Chếch 30–45° (Tối ưu)',
        labelEn: '30–45° Angled (Best)',
        supportLevel: CvAngleSupportLevel.best,
        noteVi: 'Tránh được cột tạ che tay và thấy rõ đường đi của thanh kéo.',
        noteEn: 'Avoids weight-stack occlusion and keeps the bar path clear.',
      ),
      CvAngleOption(
        angleCode: '0°/180°',
        labelVi: 'Chính diện / Sau 0°/180°',
        labelEn: 'Front / Back 0°/180°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Phù hợp nếu phía trước máy thoáng; dễ bị cột tạ che khi quay từ sau.',
        noteEn: 'Works if the front is clear; rear views are often blocked by the stack.',
      ),
      CvAngleOption(
        angleCode: '90°',
        labelVi: 'Ngang 90°',
        labelEn: 'Side 90°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Đo tốt độ ngả lưng, nhưng tay xa camera dễ bị thân người hoặc trụ máy che.',
        noteEn: 'Shows torso lean well, though the far arm may be hidden by the frame.',
      ),
    ],
    bestAngleSummaryVi:
        'Đặt máy chếch 30–45° phía trước-bên để tránh cột tạ và khung máy che cùi chỏ.',
    bestAngleSummaryEn:
        'Position the camera 30–45° front-side to keep the weight stack from blocking your elbows.',
    cameraPlacementVi:
        'Đặt máy ngang tầm ngực khi ngồi (cách 1.8–2.2 m), lấy trọn từ tay cầm trên cao đến hông và đùi giữ gối.',
    cameraPlacementEn:
        'Place the camera at seated chest height (1.8–2.2 m away), framing from top bar reach down to hips.',
    lightingTipVi:
        'Tránh đèn rọi thẳng từ trần phía sau khung máy hoặc ngược sáng cửa sổ làm tối vùng vai.',
    lightingTipEn:
        'Avoid harsh backlighting from windows or spotlights behind the cable tower.',
    blindSpotsVi: [
      'Cột tạ, dây cáp hoặc trụ khung máy che khuất khớp cùi chỏ và cổ tay.',
      'Áo rộng che đường chuyển động bả vai và làm sai lệch góc gập tay.',
      'Ngả người ra sau quá sâu khiến đầu hoặc vai trượt ra sát rìa khung hình.',
      'Người đi ngang giữa camera và ghế tập hoặc kéo giật quá nhanh trên máy < 8 FPS.',
    ],
    blindSpotsEn: [
      'The weight stack, cable, or machine uprights can block elbow and wrist landmarks.',
      'Loose clothing obscures shoulder-blade movement and elbow angle estimation.',
      'Leaning too far back can push your head or shoulders out of the frame edge.',
      'Gym passersby crossing the lens or jerky reps on < 8 FPS devices break tracking.',
    ],
  );

  static const CvExerciseGuideSpec _squatSpec = CvExerciseGuideSpec(
    module: CvExerciseModule.squat,
    titleVi: 'Squat',
    titleEn: 'Squat',
    supportedAngles: [
      CvAngleOption(
        angleCode: '30–45°',
        labelVi: 'Chếch 30–45° (Tối ưu)',
        labelEn: '30–45° Angled (Best)',
        supportLevel: CvAngleSupportLevel.best,
        noteVi: 'Cân bằng giữa đo độ sâu hông-gối và phát hiện chụm gối.',
        noteEn: 'Balances hip-knee depth tracking with knee-valgus visibility.',
      ),
      CvAngleOption(
        angleCode: '0°',
        labelVi: 'Chính diện 0°',
        labelEn: 'Front 0°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Theo dõi rõ độ chụm gối (knee valgus) và độ cân bằng hông.',
        noteEn: 'Great for tracking knee valgus and hip symmetry.',
      ),
      CvAngleOption(
        angleCode: '90°',
        labelVi: 'Ngang 90°',
        labelEn: 'Side 90°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Đo chính xác độ sâu gối và độ gập lưng, nhưng dễ bị bánh tạ che hông.',
        noteEn: 'Best for knee depth and back angle, though plates can hide the hip.',
      ),
    ],
    bestAngleSummaryVi:
        'Góc chếch 30–45° cho độ ổn định cao nhất khi vừa thấy độ sâu hông vừa thấy hai gối.',
    bestAngleSummaryEn:
        'A 30–45° front-side angle gives the most reliable view of both hip depth and knee alignment.',
    cameraPlacementVi:
        'Đặt máy ngang tầm hông (cách 2–2.5 m), lấy trọn cơ thể từ đỉnh đầu đến mắt cá chân và bàn chân.',
    cameraPlacementEn:
        'Place the camera at hip height (2–2.5 m away), keeping your head down to ankles and feet in frame.',
    lightingTipVi:
        'Đảm bảo ánh sáng đều hai bên, tránh cửa sổ sáng gắt ngay sau lưng.',
    lightingTipEn:
        'Use even side lighting and avoid bright windows directly behind you.',
    blindSpotsVi: [
      'Bánh tạ hoặc thanh chắn an toàn (safety bar) của rack che khuất khớp hông và đầu gối.',
      'Quần dài quá rộng che nếp gập hông và góc gập gối ở đáy squat.',
      'Đặt máy quá gần làm cắt mất bàn chân và mắt cá chân khỏi rìa dưới khung hình.',
      'Người đi ngang qua khung hình hoặc xuống tạ quá nhanh trên máy < 8 FPS.',
    ],
    blindSpotsEn: [
      'Barbell plates or rack safety bars can block hip and knee joints in side views.',
      'Baggy pants obscure the hip crease and knee angle at the bottom of the squat.',
      'Placing the phone too close crops out ankles and feet at the bottom edge.',
      'Passersby crossing the frame or rapid descent on < 8 FPS devices can drop reps.',
    ],
  );

  static const CvExerciseGuideSpec _pushUpSpec = CvExerciseGuideSpec(
    module: CvExerciseModule.pushUp,
    titleVi: 'Hít đất (Push-up)',
    titleEn: 'Push-up',
    supportedAngles: [
      CvAngleOption(
        angleCode: '90°',
        labelVi: 'Ngang 90° (Tối ưu)',
        labelEn: 'Side 90° (Best)',
        supportLevel: CvAngleSupportLevel.best,
        noteVi: 'Thấy rõ độ gập khuỷu tay và đường thẳng vai – hông – cổ chân.',
        noteEn: 'Clearly shows elbow depth and the shoulder–hip–ankle line.',
      ),
      CvAngleOption(
        angleCode: '30–45°',
        labelVi: 'Chếch 30–45°',
        labelEn: '30–45° Angled',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Dùng được khi phòng hẹp, vẫn phân tách được thân trên và khuỷu tay.',
        noteEn: 'Usable in tight spaces while keeping torso and elbows separated.',
      ),
      CvAngleOption(
        angleCode: '0°',
        labelVi: 'Chính diện 0° (Không khuyến nghị)',
        labelEn: 'Front 0° (Not Recommended)',
        supportLevel: CvAngleSupportLevel.notRecommended,
        noteVi: 'Thân người chồng lên nhau, AI không đo được độ sâu và độ võng lưng.',
        noteEn: 'Body parts overlap; 2D AI cannot measure elbow depth or back sag.',
      ),
    ],
    bestAngleSummaryVi:
        'Đặt máy ngang 90° sát sàn để AI thấy rõ độ sâu khuỷu tay và độ thẳng lưng.',
    bestAngleSummaryEn:
        'Place the camera low at a 90° side angle so AI can track elbow depth and back alignment.',
    angleWarningVi:
        'Không nên quay chính diện 0°: ở góc thẳng mặt, AI 2D không thể đo chính xác độ sâu khuỷu tay và độ võng lưng.',
    angleWarningEn:
        'Avoid front-facing 0°: head-on, 2D AI cannot accurately measure elbow depth or lower-back sag.',
    cameraPlacementVi:
        'Đặt máy thấp gần mặt sàn (cao 20–40 cm), cách thân người 1.5–2 m theo góc ngang 90° hoặc chếch 30–45°, lấy trọn từ đầu đến gót chân.',
    cameraPlacementEn:
        'Set the phone low near the floor (20–40 cm high), 1.5–2 m away at 90° side or 30–45°, framing head to heels.',
    lightingTipVi:
        'Đảm bảo mặt sàn đủ sáng, tránh ngược sáng từ cửa sổ thấp hoặc đèn rọi thẳng vào ống kính.',
    lightingTipEn:
        'Keep the floor well-lit and avoid low window glare or lights shining straight into the lens.',
    blindSpotsVi: [
      'Góc chính diện 0° làm vai, hông và chân chồng lên nhau khiến AI đếm sai độ sâu.',
      'Áo rộng rũ xuống che khuất đường thẳng lưng–hông khi hạ người sát sàn.',
      'Sàn tối hoặc mặc đồ tối trùng màu thảm tập làm mất điểm cổ tay và mắt cá.',
      'Chạm sát rìa khung hình, có người đi ngang hoặc hít đất quá nhanh trên máy < 8 FPS.',
    ],
    blindSpotsEn: [
      'Front 0° view overlaps shoulders, hips, and legs, making depth detection unreliable.',
      'Loose shirts drape downward and hide lower-back sag near the floor.',
      'Dark floors or dark clothing matching the mat reduce wrist and ankle contrast.',
      'Clipping frame edges, passersby, or rapid reps on < 8 FPS devices cause missed counts.',
    ],
  );

  static const CvExerciseGuideSpec _bicepCurlSpec = CvExerciseGuideSpec(
    module: CvExerciseModule.bicepCurl,
    titleVi: 'Cuốn tay trước (Bicep Curl)',
    titleEn: 'Bicep Curl',
    supportedAngles: [
      CvAngleOption(
        angleCode: '30–45°',
        labelVi: 'Chếch 30–45° (Tối ưu)',
        labelEn: '30–45° Angled (Best)',
        supportLevel: CvAngleSupportLevel.best,
        noteVi: 'Tách rõ trục vai – cùi chỏ – cổ tay mà không bị bánh tạ che mất.',
        noteEn: 'Separates shoulder–elbow–wrist cleanly without plate occlusion.',
      ),
      CvAngleOption(
        angleCode: '0°',
        labelVi: 'Chính diện 0°',
        labelEn: 'Front 0°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Thấy cả hai tay cùng lúc, nhưng góc gập cùi chỏ 2D kém rõ hơn góc chếch.',
        noteEn: 'Shows both arms together, though 2D elbow flexion is less pronounced.',
      ),
      CvAngleOption(
        angleCode: '90°',
        labelVi: 'Ngang 90°',
        labelEn: 'Side 90°',
        supportLevel: CvAngleSupportLevel.supported,
        noteVi: 'Đo góc gập cùi chỏ và độ đung đưa lưng rất rõ cho bên tay hướng về camera.',
        noteEn: 'Great for elbow angle and torso swing on the camera-facing arm.',
      ),
    ],
    bestAngleSummaryVi:
        'Đặt máy chếch 30–45° ngang tầm ngực–bụng để thấy rõ vai, cùi chỏ, cổ tay và hông.',
    bestAngleSummaryEn:
        'Place the camera at 30–45° around chest-to-waist height to track shoulder, elbow, wrist, and hip.',
    cameraPlacementVi:
        'Đặt máy ngang tầm ngực–bụng (cách 1.5–2 m), lấy trọn từ đỉnh đầu đến hông/đùi để AI kiểm tra cả độ đung đưa thân.',
    cameraPlacementEn:
        'Mount the phone at chest-to-waist height (1.5–2 m away), framing from head down to hips to detect torso swing.',
    lightingTipVi:
        'Dùng ánh sáng đều phía trước/bên, tránh ngược sáng sau lưng làm tối mặt trước cánh tay.',
    lightingTipEn:
        'Use even front or side lighting and avoid backlighting that darkens the forearm.',
    blindSpotsVi: [
      'Bánh tạ lớn hoặc thanh đòn che khuất cổ tay ở điểm co tay cao nhất.',
      'Áo tay dài rộng hoặc áo khoác che khớp cùi chỏ và điểm cố định vai.',
      'Đứng quá sát rìa khung hình hoặc vung tạ quá nhanh trên máy < 8 FPS làm nhòe khớp.',
      'Người đi ngang qua khung hình hoặc dùng tạ đơn che khuất cánh tay còn lại ở góc 90°.',
    ],
    blindSpotsEn: [
      'Large plates or dumbbells can hide the wrist landmark at peak curl contraction.',
      'Baggy long sleeves or jackets obscure elbow and shoulder joint landmarks.',
      'Standing near the frame edge or swinging rapidly on < 8 FPS devices blurs tracking.',
      'Passersby crossing the lens or single-arm occlusion in a strict 90° side view.',
    ],
  );

  static CvExerciseGuideSpec _fallbackSpec({
    required CvExerciseModule? module,
    required String titleVi,
    required String titleEn,
  }) {
    return CvExerciseGuideSpec(
      module: module,
      titleVi: titleVi,
      titleEn: titleEn,
      supportedAngles: const [
        CvAngleOption(
          angleCode: '30–45°',
          labelVi: 'Chếch 30–45° (Tối ưu)',
          labelEn: '30–45° Angled (Best)',
          supportLevel: CvAngleSupportLevel.best,
          noteVi: 'Giúp AI 2D nhìn rõ khớp chính và hạn chế che khuất giữa hai bên.',
          noteEn: 'Gives 2D AI the clearest joint separation with minimal occlusion.',
        ),
        CvAngleOption(
          angleCode: '0°',
          labelVi: 'Chính diện 0°',
          labelEn: 'Front 0°',
          supportLevel: CvAngleSupportLevel.supported,
          noteVi: 'Phù hợp để quan sát độ cân xứng hai bên trái/phải.',
          noteEn: 'Useful for checking left-right symmetry.',
        ),
        CvAngleOption(
          angleCode: '90°',
          labelVi: 'Ngang 90°',
          labelEn: 'Side 90°',
          supportLevel: CvAngleSupportLevel.supported,
          noteVi: 'Thấy rõ biên độ gập/duỗi theo chiều trước-sau nếu không bị máy che.',
          noteEn: 'Shows flexion/extension depth clearly when equipment does not block.',
        ),
      ],
      bestAngleSummaryVi:
          'Ưu tiên góc chếch 30–45° và giữ toàn bộ khớp tham gia chuyển động nằm gọn trong khung.',
      bestAngleSummaryEn:
          'Prefer a 30–45° angled view and keep every active joint comfortably inside the frame.',
      cameraPlacementVi:
          'Đặt máy cố định cách người 1.8–2.5 m, cao ngang tầm chuyển động chính và chừa khoảng trống quanh rìa khung hình.',
      cameraPlacementEn:
          'Mount the phone steadily 1.8–2.5 m away at the height of the primary joint, leaving margin around frame edges.',
      lightingTipVi:
          'Ưu tiên ánh sáng đều, tránh ngược sáng cửa sổ hoặc đèn rọi thẳng vào ống kính.',
      lightingTipEn:
          'Prefer even lighting and avoid bright windows or lights shining directly into the lens.',
      blindSpotsVi: const [
        'Áo khoác hoặc quần áo quá rộng làm AI 2D khó xác định đúng tâm khớp.',
        'Khung máy tập, thanh đòn hoặc bánh tạ che khuất khớp khi quay ngang.',
        'Người đi ngang qua khung hình hoặc cơ thể chạm sát rìa màn hình.',
        'Chuyển động giật hoặc quá nhanh trên thiết bị xử lý dưới 8 FPS có thể bỏ sót rep.',
      ],
      blindSpotsEn: const [
        'Loose jackets or baggy clothes make 2D joint estimation less accurate.',
        'Racks, barbells, or weight plates can occlude key joints from side angles.',
        'People walking through the frame or body parts clipping the frame edge.',
        'Very fast or jerky reps on devices running below 8 FPS may drop counts.',
      ],
    );
  }
}
