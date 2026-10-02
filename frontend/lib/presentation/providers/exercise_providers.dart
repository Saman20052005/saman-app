import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/exercise.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/exercise_repository_impl.dart';
import '../../services/api_client.dart';

part 'exercise_providers.g.dart';
part 'exercise_providers.freezed.dart';

/// Curated fallback exercises matching design handoff exactly
const List<Exercise> curatedExerciseLibrary = [
  Exercise(
    id: 'db-bench-press',
    slug: 'dumbbell-bench-press',
    name: 'Dumbbell Bench Press',
    nameVi: 'Đẩy ngực với tạ đơn',
    muscleGroup: 'Chest',
    targetMuscles: ['Chest', 'Pectoralis Major'],
    secondaryMuscles: ['Triceps', 'Shoulders', 'Anterior Deltoid'],
    equipment: ['Dumbbells', 'Flat bench'],
    difficulty: 'intermediate',
    thumbnailUrl:
        'https://lh3.googleusercontent.com/aida-public/AB6AXuAzZ8AN5eaYmQP_EvKw44Mfp-YxaGOwX40UdqgBZjq20Um1LTYduBYBVa8dm-3IgrFmdHVPhbSBhdaGgY3JAx_DSJvKI0-TULkJ_L7KS4B7tOsxq5n5RPpuFC32VeGylN5bZ6COF4ZIwwEVV2MM22TwFI4dDyuMTTG3O7mSlnxsrLuFa6VkeJIc9FhiyaIQ-x7ZuA9rV7PCr1S-qGYpCbjJF1VEaQ1ycjOtMsLs4ys63WeZ4Yo7E1VD',
    defaultSets: 4,
    defaultReps: '8-10',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Keep your feet firmly planted on the floor',
      'Maintain a slight natural arch in lower back',
      'Lower dumbbells with control to mid-chest level',
      'Press vertically until arms are fully extended',
    ],
    commonMistakes: [
      'Flaring elbows out at 90 degrees',
      'Bouncing dumbbells off chest',
      'Lifting feet off the floor during press',
    ],
  ),
  Exercise(
    id: 'lat-pulldown',
    slug: 'lat-pulldown',
    name: 'Lat Pulldown',
    nameVi: 'Kéo xô máy',
    muscleGroup: 'Back',
    targetMuscles: ['Back', 'Latissimus Dorsi'],
    secondaryMuscles: ['Biceps', 'Rear Deltoid'],
    equipment: ['Cable Machine', 'Lat Bar'],
    difficulty: 'beginner',
    thumbnailUrl:
        'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?auto=format&fit=crop&w=600&q=80',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Grip slightly wider than shoulder width',
      'Pull down towards upper chest with elbows leading',
      'Squeeze lats at the bottom',
    ],
    commonMistakes: [
      'Leaning back excessively',
      'Pulling behind the neck',
    ],
  ),
  Exercise(
    id: 'seated-cable-row',
    slug: 'seated-cable-row',
    name: 'Seated Cable Row',
    nameVi: 'Kéo cáp ngồi',
    muscleGroup: 'Back',
    targetMuscles: ['Back', 'Rhomboids', 'Mid Traps'],
    secondaryMuscles: ['Biceps', 'Forearms'],
    equipment: ['Cable Machine', 'V-Bar'],
    difficulty: 'intermediate',
    thumbnailUrl:
        'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?auto=format&fit=crop&w=600&q=80',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Keep spine upright with neutral curvature',
      'Initiate pull by retracting shoulder blades',
      'Pause and squeeze at the torso',
    ],
    commonMistakes: [
      'Rounding the lower back',
      'Using excessive body swing momentum',
    ],
  ),
  Exercise(
    id: 'db-shoulder-press',
    slug: 'dumbbell-shoulder-press',
    name: 'Dumbbell Shoulder Press',
    nameVi: 'Đẩy vai với tạ đơn',
    muscleGroup: 'Shoulders',
    targetMuscles: ['Shoulders', 'Anterior Deltoid'],
    secondaryMuscles: ['Triceps', 'Upper Chest'],
    equipment: ['Dumbbells', 'Incline/Vertical Bench'],
    difficulty: 'intermediate',
    thumbnailUrl:
        'https://images.unsplash.com/photo-1541534741688-6078c6bfb5c5?auto=format&fit=crop&w=600&q=80',
    defaultSets: 4,
    defaultReps: '8-10',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Keep core tight and ribs down',
      'Press weights directly overhead',
      'Control descent to ear level',
    ],
    commonMistakes: [
      'Hyperextending the lower back',
      'Locking out elbows aggressively at the top',
    ],
  ),
  Exercise(
    id: 'push-up',
    slug: 'push-up',
    name: 'Push-Up',
    nameVi: 'Hít đất',
    muscleGroup: 'Chest',
    targetMuscles: ['Chest', 'Triceps'],
    secondaryMuscles: ['Core', 'Anterior Deltoid'],
    equipment: ['Bodyweight'],
    difficulty: 'beginner',
    thumbnailUrl:
        'https://images.unsplash.com/photo-1598971639058-fab3c3109a00?auto=format&fit=crop&w=600&q=80',
    defaultSets: 3,
    defaultReps: '12-15',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Keep body in a rigid plank line',
      'Elbows tracking at 45 degrees',
      'Lower chest until nearly touching floor',
    ],
    commonMistakes: [
      'Sagging hips',
      'Flaring elbows out 90 degrees',
    ],
  ),

  // --- Arms (2 exercises) ---
  Exercise(
    id: 'db-bicep-curl',
    slug: 'dumbbell-bicep-curl',
    name: 'Dumbbell Bicep Curl',
    nameVi: 'Cuốn tạ đơn tập cơ tay trước',
    muscleGroup: 'Arms',
    targetMuscles: ['Arms', 'Biceps'],
    secondaryMuscles: ['Forearms', 'Brachialis'],
    equipment: ['Dumbbells'],
    difficulty: 'beginner',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Keep elbows pinned close to your torso',
      'Curl dumbbells upward while rotating wrists into supination',
      'Squeeze biceps at the peak, then lower under full control',
    ],
    commonMistakes: [
      'Swinging torso or using momentum to lift',
      'Allowing elbows to drift excessively forward',
    ],
  ),
  Exercise(
    id: 'triceps-rope-pushdown',
    slug: 'triceps-rope-pushdown',
    name: 'Triceps Rope Pushdown',
    nameVi: 'Kéo cáp dây thừng tập tay sau',
    muscleGroup: 'Arms',
    targetMuscles: ['Arms', 'Triceps'],
    secondaryMuscles: ['Forearms'],
    equipment: ['Cable Machine', 'Rope Attachment'],
    difficulty: 'beginner',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '12-15',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Pin elbows firmly at your sides throughout the movement',
      'Extend arms downward, spreading rope ends slightly at the bottom',
      'Control the return until forearms reach parallel to the floor',
    ],
    commonMistakes: [
      'Flaring elbows outward during extension',
      'Leaning too far over the cable stack',
    ],
  ),

  // --- Lower Body (6 exercises covering Quads, Glutes, Hamstrings, Calves) ---
  Exercise(
    id: 'barbell-back-squat',
    slug: 'barbell-back-squat',
    name: 'Barbell Back Squat',
    nameVi: 'Gánh tạ đòn ngang lưng',
    muscleGroup: 'Quads',
    targetMuscles: ['Quads', 'Quadriceps'],
    secondaryMuscles: ['Glutes', 'Hamstrings', 'Core'],
    equipment: ['Barbell', 'Squat Rack'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 4,
    defaultReps: '6-8',
    restSeconds: 120,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Rest barbell securely across upper traps with chest proud',
      'Hinge hips back and bend knees tracking in line with toes',
      'Descend until thighs are at least parallel to the floor',
      'Drive through midfoot and heels to return upright',
    ],
    commonMistakes: [
      'Knees caving inward during ascent',
      'Heels lifting off the floor',
      'Rounding the lower back in the hole',
    ],
  ),
  Exercise(
    id: 'romanian-deadlift',
    slug: 'romanian-deadlift',
    name: 'Romanian Deadlift',
    nameVi: 'Kéo tạ đùi sau kiểu Rumani',
    muscleGroup: 'Hamstrings',
    targetMuscles: ['Hamstrings'],
    secondaryMuscles: ['Glutes', 'Lower Back', 'Forearms'],
    equipment: ['Barbell'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-10',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Hinge at hips with a soft, fixed bend in knees',
      'Keep barbell close to shins with a flat neutral back',
      'Lower until feeling deep hamstring stretch, then drive hips forward',
    ],
    commonMistakes: [
      'Rounding the lumbar spine during descent',
      'Squatting downward instead of hinging hips back',
    ],
  ),
  Exercise(
    id: 'barbell-hip-thrust',
    slug: 'barbell-hip-thrust',
    name: 'Barbell Hip Thrust',
    nameVi: 'Đẩy hông tạ đòn tập cơ mông',
    muscleGroup: 'Glutes',
    targetMuscles: ['Glutes'],
    secondaryMuscles: ['Hamstrings', 'Adductors'],
    equipment: ['Barbell', 'Flat bench'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 4,
    defaultReps: '10-12',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Rest upper back against bench with barbell padded across hip crease',
      'Set feet shoulder-width apart so shins are vertical at top lockout',
      'Drive hips upward, tuck chin slightly, and achieve full glute lockout',
    ],
    commonMistakes: [
      'Hyperextending lumbar spine at top',
      'Feet placed too far forward or too close to hips',
    ],
  ),
  Exercise(
    id: 'leg-press',
    slug: 'leg-press',
    name: 'Leg Press',
    nameVi: 'Đạp đùi trên máy nghiêng',
    muscleGroup: 'Quads',
    targetMuscles: ['Quads', 'Quadriceps'],
    secondaryMuscles: ['Glutes', 'Calves'],
    equipment: ['Leg Press Machine'],
    difficulty: 'beginner',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 90,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Plant back and hips flat against padded backrest',
      'Position feet hip-width on platform center',
      'Lower sled smoothly until knees reach 90-degree angle',
      'Press through full foot without locking knees abruptly',
    ],
    commonMistakes: [
      'Allowing lower back to curl off the backrest',
      'Violently snapping knees into full hyperextension',
    ],
  ),
  Exercise(
    id: 'lying-leg-curl',
    slug: 'lying-leg-curl',
    name: 'Lying Leg Curl',
    nameVi: 'Móc đùi sau nằm trên máy',
    muscleGroup: 'Hamstrings',
    targetMuscles: ['Hamstrings'],
    secondaryMuscles: ['Calves'],
    equipment: ['Leg Curl Machine'],
    difficulty: 'beginner',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '12-15',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Lie face down with roller pad positioned just below calves',
      'Keep hips pressed flat against bench throughout curl',
      'Curl heels toward glutes smoothly and pause at top contraction',
    ],
    commonMistakes: [
      'Lifting hips off bench to yank the weight',
      'Letting the weight plates crash down between reps',
    ],
  ),
  Exercise(
    id: 'standing-calf-raise',
    slug: 'standing-calf-raise',
    name: 'Standing Calf Raise',
    nameVi: 'Nhón bắp chân đứng',
    muscleGroup: 'Calves',
    targetMuscles: ['Calves'],
    secondaryMuscles: ['Foot stabilizers'],
    equipment: ['Calf Raise Machine'],
    difficulty: 'beginner',
    thumbnailUrl: '',
    defaultSets: 4,
    defaultReps: '12-15',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Balls of feet on edge of platform with heels hanging free',
      'Lower heels into a full stretch with knees straight',
      'Press through balls of feet to peak height and pause for 1 second',
    ],
    commonMistakes: [
      'Bouncing rapidly without pausing in stretch or contraction',
      'Bending knees to generate momentum',
    ],
  ),

  // --- Core (4 exercises covering Abs and Obliques) ---
  Exercise(
    id: 'plank',
    slug: 'plank',
    name: 'Plank',
    nameVi: 'Giữ tư thế plank chống khuỷu',
    muscleGroup: 'Abs',
    targetMuscles: ['Abs', 'Core'],
    secondaryMuscles: ['Shoulders', 'Glutes'],
    equipment: ['Bodyweight'],
    difficulty: 'beginner',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '45-60',
    restSeconds: 60,
    repType: 'seconds',
    cvSupported: false,
    cues: [
      'Place forearms on floor with elbows directly under shoulders',
      'Maintain rigid straight line from head to heels',
      'Brace abdominal wall and squeeze glutes firmly',
    ],
    commonMistakes: [
      'Sagging hips towards floor',
      'Piking hips upward to relieve abdominal tension',
      'Holding breath instead of breathing rhythmically',
    ],
  ),
  Exercise(
    id: 'hanging-leg-raise',
    slug: 'hanging-leg-raise',
    name: 'Hanging Leg Raise',
    nameVi: 'Treo xà đơn nâng chân gập bụng',
    muscleGroup: 'Abs',
    targetMuscles: ['Abs', 'Hip Flexors'],
    secondaryMuscles: ['Forearms', 'Lats'],
    equipment: ['Pull-up Bar'],
    difficulty: 'advanced',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 75,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Hang from bar with active engaged shoulders',
      'Raise legs by curling pelvis upward toward ribs',
      'Lower legs under strict eccentric control without swinging',
    ],
    commonMistakes: [
      'Swinging torso to kick legs upward with momentum',
      'Allowing shoulders to disengage and shrug into neck',
    ],
  ),
  Exercise(
    id: 'cable-woodchopper',
    slug: 'cable-woodchopper',
    name: 'Cable Woodchopper',
    nameVi: 'Kéo cáp vặn sườn tập cơ liên sườn',
    muscleGroup: 'Obliques',
    targetMuscles: ['Obliques', 'Core'],
    secondaryMuscles: ['Shoulders'],
    equipment: ['Cable Machine'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '10-12',
    restSeconds: 60,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Set cable high, grip handle with both hands and arms straight',
      'Rotate torso downward diagonally across body by pivoting rear foot',
      'Control return slowly along diagonal track while keeping core braced',
    ],
    commonMistakes: [
      'Pulling with arms rather than rotating core',
      'Rounding the spine during the twist',
    ],
  ),
  Exercise(
    id: 'ab-wheel-rollout',
    slug: 'ab-wheel-rollout',
    name: 'Ab Wheel Rollout',
    nameVi: 'Lăn bánh xe tập cơ bụng',
    muscleGroup: 'Abs',
    targetMuscles: ['Abs', 'Core'],
    secondaryMuscles: ['Lats', 'Shoulders'],
    equipment: ['Ab Wheel'],
    difficulty: 'intermediate',
    thumbnailUrl: '',
    defaultSets: 3,
    defaultReps: '8-10',
    restSeconds: 75,
    repType: 'reps',
    cvSupported: false,
    cues: [
      'Kneel on floor holding wheel with arms straight beneath shoulders',
      'Roll forward smoothly while bracing core in posterior pelvic tilt',
      'Pull back using abdominal contraction without sagging lower back',
    ],
    commonMistakes: [
      'Letting lower back sag into hyperextension',
      'Initiating return with hips instead of contracting abs',
    ],
  ),
];

/// Provider for verified exercise library items matching the design handoff
final exerciseLibraryListProvider = FutureProvider<List<Exercise>>((ref) async {
  // In the frontend UI phase, return curatedExerciseLibrary directly (17 exercises).
  // ExerciseRepository and exerciseRepositoryProvider remain preserved for subsequent backend integration.
  return curatedExerciseLibrary;
});


@riverpod
Future<List<Exercise>> exercisesByMuscle(
  ExercisesByMuscleRef ref, {
  required String muscleGroupSlug,
  String difficulty = 'all',
  String search = '',
}) async {
  final repo = ref.watch(exerciseRepositoryProvider);
  return repo.getExercisesByMuscleGroup(
    muscleGroupSlug: muscleGroupSlug,
    difficulty: difficulty == 'all' ? null : difficulty,
    search: search.isEmpty ? null : search,
  );
}

@riverpod
ExerciseRepository exerciseRepository(ExerciseRepositoryRef ref) {
  final dio = ref.watch(dioProvider);
  return ExerciseRepositoryImpl(dio: dio);
}

// Provider cho filter state (dùng StateNotifier)
@riverpod
class ExerciseFilters extends _$ExerciseFilters {
  @override
  ExerciseFilterState build() => const ExerciseFilterState();

  void setDifficulty(String difficulty) {
    state = state.copyWith(difficulty: difficulty);
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }

  void reset() {
    state = const ExerciseFilterState();
  }
}

@freezed
class ExerciseFilterState with _$ExerciseFilterState {
  const factory ExerciseFilterState({
    @Default('all') String difficulty,
    @Default('') String search,
  }) = _ExerciseFilterState;
}
