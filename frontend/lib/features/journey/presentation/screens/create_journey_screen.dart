import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/journey_models.dart';
import '../providers/journey_providers.dart';

class CreateJourneyScreen extends ConsumerStatefulWidget {
  final VoidCallback? onDismiss;

  const CreateJourneyScreen({super.key, this.onDismiss});

  @override
  ConsumerState<CreateJourneyScreen> createState() => _CreateJourneyScreenState();
}

class _CreateJourneyScreenState extends ConsumerState<CreateJourneyScreen> {
  JourneyFocus _selectedFocus = JourneyFocus.hybrid;
  int _selectedDays = 14; // Default policy: 14 days
  bool _enableReminder = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentJourney = ref.read(journeyControllerProvider).journey;
      if (currentJourney != null && currentJourney.isActive) {
        setState(() {
          _selectedFocus = currentJourney.focus;
          _selectedDays = currentJourney.totalDays;
          if (currentJourney.reminderTime != null && currentJourney.reminderTime!.contains(':')) {
            final parts = currentJourney.reminderTime!.split(':');
            final h = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            if (h != null && m != null) {
              _reminderTime = TimeOfDay(hour: h, minute: m);
              _enableReminder = true;
            }
          }
        });
      }
    });
  }

  String _getDurationHelperText(int days) {
    switch (days) {
      case 7:
        return '1 tuần để làm quen và khởi động.';
      case 14:
        return '2 tuần để hình thành nhịp sinh hoạt.';
      case 30:
        return '1 tháng để bứt phá toàn diện thể chất.';
      default:
        return '$days ngày rèn luyện kỷ luật.';
    }
  }

  Future<void> _selectReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10B981),
              onPrimary: Color(0xFF0C0D0E),
              surface: Color(0xFF16171B),
              onSurface: Color(0xFFF3F4F6),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _reminderTime = picked);
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final reminderStr = _enableReminder
        ? '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}'
        : null;

    final success = await ref.read(journeyControllerProvider.notifier).createJourney(
          focus: _selectedFocus,
          totalDays: _selectedDays,
          reminderTime: reminderStr,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hành trình mới đã được khởi tạo thành công!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      final err = ref.read(journeyControllerProvider).errorMessage ?? 'Không thể tạo hành trình.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: $err'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0D0E),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // TOP BAR & HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF94979E)),
                    onPressed: () {
                      if (widget.onDismiss != null) {
                        widget.onDismiss!();
                      } else {
                        Navigator.of(context).pop(false);
                      }
                    },
                  ),
                  if (widget.onDismiss != null)
                    TextButton(
                      onPressed: widget.onDismiss,
                      child: const Text(
                        'Để sau',
                        style: TextStyle(
                          color: Color(0xFF94979E),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // MAIN SCROLLABLE CONTENT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tạo hành trình',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF3F4F6),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Thói quen nhỏ, thay đổi bền lâu.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF94979E),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // SECTION 1: FOCUS SELECTION
                    const Text(
                      'Bạn muốn tập trung vào điều gì?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFocusOption(
                      focus: JourneyFocus.workout,
                      title: 'Tập luyện',
                      icon: Icons.fitness_center_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildFocusOption(
                      focus: JourneyFocus.nutrition,
                      title: 'Dinh dưỡng',
                      icon: Icons.restaurant_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildFocusOption(
                      focus: JourneyFocus.hybrid,
                      title: 'Kết hợp cả hai',
                      icon: Icons.sync_alt_rounded,
                    ),
                    const SizedBox(height: 28),

                    // SECTION 2: DURATION SELECTION
                    const Text(
                      'Thời gian cam kết?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16171B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF26282F), width: 1),
                      ),
                      child: Row(
                        children: [
                          _buildDurationTab(7, '7 ngày'),
                          _buildDurationTab(14, '14 ngày'),
                          _buildDurationTab(30, '30 ngày'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getDurationHelperText(_selectedDays),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF94979E),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // SECTION 3: DAILY REMINDER
                    const Text(
                      'Nhắc nhở hàng ngày',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF3F4F6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16171B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF26282F), width: 1),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.notifications_none_rounded, color: Color(0xFF94979E), size: 20),
                                  SizedBox(width: 12),
                                  Text(
                                    'Bật nhắc nhở',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFFF3F4F6),
                                    ),
                                  ),
                                ],
                              ),
                              Switch.adaptive(
                                value: _enableReminder,
                                activeColor: const Color(0xFF10B981),
                                activeTrackColor: const Color(0xFF10B981).withOpacity(0.4),
                                inactiveTrackColor: const Color(0xFF212328),
                                onChanged: (val) => setState(() => _enableReminder = val),
                              ),
                            ],
                          ),
                          if (_enableReminder) ...[
                            const Divider(color: Color(0xFF26282F), height: 24),
                            InkWell(
                              onTap: _selectReminderTime,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.schedule_rounded, color: Color(0xFF94979E), size: 20),
                                        SizedBox(width: 12),
                                        Text(
                                          'Giờ nhắc',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF94979E),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFF3F4F6),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right, color: Color(0xFF94979E), size: 18),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // STICKY BOTTOM ACTION BAR
            Container(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
              decoration: const BoxDecoration(
                color: Color(0xFF0C0D0E),
                border: Border(top: BorderSide(color: Color(0xFF26282F), width: 1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF9FAFB),
                        foregroundColor: const Color(0xFF0C0D0E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0C0D0E),
                              ),
                            )
                          : const Text(
                              'Bắt đầu hành trình',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bạn có thể điều chỉnh giờ nhắc bất kỳ lúc nào.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94979E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusOption({
    required JourneyFocus focus,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedFocus == focus;

    return InkWell(
      onTap: () => setState(() => _selectedFocus = focus),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16171B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : const Color(0xFF26282F),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF10B981) : const Color(0xFF94979E),
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFF3F4F6),
                ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFF383A42),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: Color(0xFF0C0D0E),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationTab(int days, String label) {
    final isSelected = _selectedDays == days;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedDays = days),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF9FAFB) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? const Color(0xFF0C0D0E) : const Color(0xFF94979E),
            ),
          ),
        ),
      ),
    );
  }
}
