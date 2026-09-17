import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/api_client.dart';
import '../features/workout/data/models/workout_plan_model.dart';

class CreatePlanScreen extends StatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  State<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends State<CreatePlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _durationController = TextEditingController();
  final _kcalController = TextEditingController();

  // Danh sách bài tập động
  final List<Map<String, dynamic>> _exercises = [];

  String _selectedCategory = 'Chest';
  String _selectedLevel = 'Beginner';
  bool _isLoading = false;

  final List<String> _categories = [
    'Chest',
    'Back',
    'Legs',
    'Shoulder',
    'Arms',
    'Abs',
    'Cardio',
    'Full Body'
  ];
  final List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

  void _addExercise() {
    setState(() {
      _exercises.add({'name': '', 'reps': '3 sets x 12 reps', 'set_count': 3});
    });
  }

  void _removeExercise(int index) {
    setState(() {
      _exercises.removeAt(index);
    });
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add at least 1 exercise")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Chuyển đổi sang Model để đảm bảo đúng format Backend
      final List<WorkoutExerciseModel> exerciseModels = _exercises
          .map((e) => WorkoutExerciseModel(
                name: e['name'],
                reps: e['reps'].toString(),
                setCount: e['set_count'] ?? 3,
              ))
          .toList();

      final planModel = WorkoutPlanModel(
        title: _titleController.text,
        category: _selectedCategory,
        level: _selectedLevel,
        duration: int.tryParse(_durationController.text) ?? 30,
        kcal: int.tryParse(_kcalController.text) ?? 200,
        exercises: exerciseModels,
      );

      final response = await ApiClient.dio.post(
        ApiConfig.createPlanEndpoint,
        data: planModel.toJson(),
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        Navigator.pop(context, true); // Trả về true để màn hình trước reload
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Plan Created Successfully! 🔥"),
            backgroundColor: Colors.green));
      } else {
        final errorMsg = response.data?['detail'] ?? "Failed to create plan";
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Custom Plan")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: "Plan Name (e.g., Morning Cardio)",
                  border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? "Required" : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField(
                    value: _selectedCategory,
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCategory = v!),
                    decoration: const InputDecoration(
                        labelText: "Category", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField(
                    value: _selectedLevel,
                    items: _levels
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedLevel = v!),
                    decoration: const InputDecoration(
                        labelText: "Level", border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Duration (min)",
                        border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _kcalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Est. Calories",
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Exercises",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                    onPressed: _addExercise,
                    icon: const Icon(Icons.add_circle,
                        color: Colors.green, size: 30))
              ],
            ),
            ..._exercises.asMap().entries.map((entry) {
              int idx = entry.key;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _exercises[idx]['name'],
                              decoration: InputDecoration(
                                  labelText: "Exercise Name #${idx + 1}"),
                              onChanged: (val) => _exercises[idx]['name'] = val,
                            ),
                          ),
                          IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeExercise(idx))
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _exercises[idx]['reps'],
                              decoration: const InputDecoration(
                                  labelText: "Reps (e.g. 4x12)"),
                              onChanged: (val) => _exercises[idx]['reps'] = val,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              initialValue:
                                  _exercises[idx]['set_count'].toString(),
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: "Sets"),
                              onChanged: (val) => _exercises[idx]['set_count'] =
                                  int.tryParse(val) ?? 3,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 30),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _savePlan,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("CREATE PLAN"),
              ),
            )
          ],
        ),
      ),
    );
  }
}
