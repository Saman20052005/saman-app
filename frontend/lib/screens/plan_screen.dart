import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/api_config.dart';
import '../widgets/app_logo.dart'; // Đảm bảo đã tạo file này
import '../services/api_client.dart';

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

  // Theme Colors
  final Color _primaryColor = const Color(0xFF1E1E1E);
  final Color _accentColor = const Color(0xFF00E676);
  final Color _bgGrey = const Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    _addExercise();
  }

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
    if (_exercises.any((e) => e['name'].toString().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please name all exercises")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final body = {
        "title": _titleController.text,
        "category": _selectedCategory,
        "level": _selectedLevel,
        "duration": "${_durationController.text} min",
        "kcal": int.tryParse(_kcalController.text) ?? 200,
        "exercises": _exercises
      };

      final response = await ApiClient.dio.post(
        ApiConfig.createPlanEndpoint,
        data: body,
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✨ SAMAN Plan Created Successfully!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        throw Exception("Failed to create plan");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGrey,
      appBar: AppBar(
        // Cập nhật AppBar với Logo SAMAN
        leading: const Padding(
          padding: EdgeInsets.all(12.0),
          child: AppLogo(size: 30),
        ),
        title: const Text("SAMAN | Designer",
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSectionLabel("PLAN DETAILS"),
                  _buildBasicInfoCard(),
                  const SizedBox(height: 24),
                  _buildSectionLabel("CONFIGURATION"),
                  _buildSelector(
                      "Target Muscle",
                      _categories,
                      _selectedCategory,
                      (val) => setState(() => _selectedCategory = val)),
                  const SizedBox(height: 16),
                  _buildSelector("Difficulty", _levels, _selectedLevel,
                      (val) => setState(() => _selectedLevel = val)),
                  const SizedBox(height: 24),
                  _buildSectionLabel("EXERCISES (${_exercises.length})"),
                  ..._exercises
                      .asMap()
                      .entries
                      .map((entry) => _buildExerciseItem(entry.key)),
                  const SizedBox(height: 10),
                  _buildAddButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            _buildBottomDock(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        label,
        style: TextStyle(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            decoration: const InputDecoration(
              labelText: "Workout Name",
              hintText: "e.g., SAMAN Power Chest",
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
              // Thay thế Icon thường bằng Logo thương hiệu nhỏ
              prefixIcon: Padding(
                padding: EdgeInsets.all(12.0),
                child: AppLogo(size: 24),
              ),
            ),
            validator: (v) => v!.isEmpty ? "Required" : null,
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
                    prefixIcon: Icon(Icons.timer_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _kcalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Est. Kcal",
                    prefixIcon: Icon(Icons.local_fire_department_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSelector(String title, List<String> options, String selected,
      Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.map((option) {
              final isSelected = selected == option;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (_) => onSelect(option),
                  selectedColor: _primaryColor,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                          color: isSelected
                              ? Colors.transparent
                              : Colors.grey.shade300)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseItem(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: Center(
                    child: Text("${index + 1}",
                        style: TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _exercises[index]['name'],
                  decoration: const InputDecoration(
                    hintText: "Exercise Name",
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  onChanged: (val) => _exercises[index]['name'] = val,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                onPressed: () => _removeExercise(index),
              )
            ],
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: _exercises[index]['reps'],
                  decoration: const InputDecoration(
                    labelText: "Details",
                    hintText: "4 sets x 12 reps",
                    border: InputBorder.none,
                    icon: Icon(Icons.format_list_bulleted, size: 18),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (val) => _exercises[index]['reps'] = val,
                ),
              ),
              Container(width: 1, height: 24, color: Colors.grey.shade300),
              Expanded(
                flex: 1,
                child: TextFormField(
                  initialValue: _exercises[index]['set_count'].toString(),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: "Sets",
                    border: InputBorder.none,
                  ),
                  onChanged: (val) =>
                      _exercises[index]['set_count'] = int.tryParse(val) ?? 3,
                ),
              ),
            ],
          )
        ],
      ),
    ).animate().fadeIn().slideX();
  }

  Widget _buildAddButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _addExercise,
        style: TextButton.styleFrom(
            foregroundColor: _primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(color: Colors.grey.shade300))),
        icon: const Icon(Icons.add),
        label: const Text("Add Another Exercise"),
      ),
    );
  }

  Widget _buildBottomDock() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _savePlan,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text("SAVE WORKOUT PLAN",
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1)),
          ),
        ),
      ),
    );
  }
}
