import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/exercise.dart';
import '../providers/active_workout_providers.dart';
import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_colors.dart';

class SetLoggingCard extends ConsumerStatefulWidget {
  final Exercise exercise;
  final int setNumber;

  const SetLoggingCard({
    super.key,
    required this.exercise,
    required this.setNumber,
  });

  @override
  ConsumerState<SetLoggingCard> createState() => _SetLoggingCardState();
}

class _SetLoggingCardState extends ConsumerState<SetLoggingCard> {
  late int _reps;
  late double _weight;
  bool _resting = false;
  int _restSecondsLeft = 0;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(activeWorkoutNotifierProvider.notifier);
    final setState = notifier.currentSetState;
    _reps = setState.reps;
    _weight = setState.weight;
    _resting = setState.isResting;
    _restSecondsLeft = setState.restSecondsLeft;
  }

  void _updateReps(int delta) {
    setState(() => _reps = (_reps + delta).clamp(0, 999));
    ref.read(activeWorkoutNotifierProvider.notifier).updateReps(_reps);
  }

  void _updateWeight(double delta) {
    setState(() => _weight = (_weight + delta).clamp(0.0, 500.0));
    ref.read(activeWorkoutNotifierProvider.notifier).updateWeight(_weight);
  }

  void _startRest() {
    setState(() {
      _resting = true;
      _restSecondsLeft = widget.exercise.restSeconds;
    });
    ref.read(activeWorkoutNotifierProvider.notifier).startRest();
    _tickRest();
  }

  void _tickRest() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_resting) return;
      ref.read(activeWorkoutNotifierProvider.notifier).tickRest();
      final newState =
          ref.read(activeWorkoutNotifierProvider.notifier).currentSetState;
      setState(() {
        _restSecondsLeft = newState.restSecondsLeft;
        _resting = newState.isResting;
      });
      if (_resting) _tickRest();
    });
  }

  void _skipRest() {
    setState(() {
      _resting = false;
      _restSecondsLeft = 0;
    });
    ref.read(activeWorkoutNotifierProvider.notifier).skipRest();
  }

  void _completeSet() {
    if (_resting) return;
    ref.read(activeWorkoutNotifierProvider.notifier).completeCurrentSet();
    // Cập nhật UI để hiển thị set tiếp theo
    final newSetState =
        ref.read(activeWorkoutNotifierProvider.notifier).currentSetState;
    setState(() {
      _reps = newSetState.reps;
      _weight = newSetState.weight;
      _resting = newSetState.isResting;
      _restSecondsLeft = newSetState.restSecondsLeft;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // REPS & WEIGHT
            Row(
              children: [
                // REPS
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'REPS',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_reps',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => _updateReps(-1),
                            icon: const Icon(Icons.remove_circle, size: 36),
                          ),
                          IconButton(
                            onPressed: () => _updateReps(1),
                            icon: const Icon(Icons.add_circle, size: 36),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, indent: 20, endIndent: 20),
                // WEIGHT
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'WEIGHT',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_weight.toStringAsFixed(0)} kg',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => _updateWeight(-2.5),
                            icon: const Icon(Icons.remove_circle, size: 36),
                          ),
                          IconButton(
                            onPressed: () => _updateWeight(2.5),
                            icon: const Icon(Icons.add_circle, size: 36),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Rest timer
            if (_resting)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _restSecondsLeft / widget.exercise.restSeconds,
                    backgroundColor: Colors.grey[200],
                    color: AppColors.primary,
                    minHeight: 12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Rest: ${_restSecondsLeft}s',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _skipRest,
                        child: const Text('Bỏ qua'),
                      ),
                    ],
                  ),
                ],
              ),
            const Spacer(),
            // DONE button
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: _resting ? _skipRest : _completeSet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  _resting ? 'BỎ QUA NGHỈ' : 'DONE — NGHỈ',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
