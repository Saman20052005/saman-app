import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/active_workout_providers.dart';
import '../providers/workout_history_providers.dart';
import '../tokens/saman_workout_tokens.dart';

class WorkoutReviewSheet extends ConsumerWidget {
  const WorkoutReviewSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeWorkoutSessionProvider);
    final saving = ref.watch(activeSessionSaverProvider);
    return PopScope(
      canPop: !saving.isLoading,
      child: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsetsDirectional.all(SamanWorkoutTokens.spacingLg),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  color: SamanWorkoutTokens.textPrimary,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Workout Review & Save'),
                const SizedBox(height: SamanWorkoutTokens.spacingMd),
                Text(session.title),
                Text('${session.completedSetsCount} logged sets • '
                    '${session.elapsedSeconds} seconds active'),
                const SizedBox(height: SamanWorkoutTokens.spacingMd),
                const Text('Local / demo only. Stored in memory until the app '
                    'restarts. Not synced to a server.'),
                if (session.completedSetsCount == 0)
                  const Text('Log at least one set before saving.'),
                if (saving.hasError)
                  const Text('Could not save this session. Please retry.'),
                const SizedBox(height: SamanWorkoutTokens.spacingLg),
                FilledButton(
                  key: const ValueKey('save_session_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: SamanWorkoutTokens.buttonPrimary,
                    foregroundColor: SamanWorkoutTokens.buttonPrimaryText,
                  ),
                  onPressed: saving.isLoading || session.completedSetsCount == 0
                      ? null
                      : () async {
                          final saved = await ref
                              .read(activeSessionSaverProvider.notifier)
                              .saveCurrentSession();
                          if (context.mounted && saved) {
                            Navigator.of(context).pop(true);
                          }
                        },
                  child: Text(saving.isLoading ? 'Saving…' : 'Save Session'),
                ),
                TextButton(
                  key:
                      const ValueKey('active_workout_review_understood_button'),
                  style: TextButton.styleFrom(
                    foregroundColor: SamanWorkoutTokens.textSecondary,
                  ),
                  onPressed: saving.isLoading
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Keep Training'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
