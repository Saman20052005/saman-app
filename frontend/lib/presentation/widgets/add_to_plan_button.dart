import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/exercise.dart';
import '../../core/constants/app_dimens.dart';
import '../providers/create_plan_providers.dart';
import '../screens/create_plan_screen.dart';

class AddToPlanButton extends ConsumerWidget {
  final Exercise exercise;

  const AddToPlanButton({super.key, required this.exercise});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () async {
          // Kiểm tra xem có đang ở trong CreatePlanScreen không?
          // Nếu không, mở CreatePlanScreen và thêm Exercise đó vào.
          // Cách đơn giản: luôn mở CreatePlanScreen với Exercise được chọn.
          final isInCreatePlan =
              ModalRoute.of(context)?.settings.name == '/create-plan';
          if (!isInCreatePlan) {
            // Điều hướng đến CreatePlanScreen và truyền Exercise
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CreatePlanScreen(),
                settings: const RouteSettings(name: '/create-plan'),
              ),
            );
            // Sau khi quay lại, nếu đã thêm bài tập từ đó thì không cần làm gì thêm.
            // Nếu vẫn muốn thêm vào Plan hiện tại, có thể dùng ref.read.
          }
          // Thêm exercise vào provider
          ref.read(createPlanNotifierProvider.notifier).addExercise(exercise);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã thêm "${exercise.name}" vào Plan'),
              action: SnackBarAction(
                label: 'Xem Plan',
                onPressed: () {
                  // Nếu chưa mở CreatePlanScreen thì mở
                  if (!isInCreatePlan) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreatePlanScreen(),
                        settings: const RouteSettings(name: '/create-plan'),
                      ),
                    );
                  }
                },
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusL),
          ),
        ),
        child: const Text(
          'Thêm vào Plan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
