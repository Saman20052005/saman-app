import 'package:flutter/material.dart';
import '../tokens/saman_ig_tokens.dart';

enum DraftDiscardAction { saveDraft, discard, cancel }

class DraftDiscardDialog extends StatelessWidget {
  const DraftDiscardDialog({super.key});

  static Future<DraftDiscardAction?> show(BuildContext context) {
    return showModalBottomSheet<DraftDiscardAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const DraftDiscardDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ig = SamanIgTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ig.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ig.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Lưu bản nháp bài viết?',
            style: ig.displayTitle(fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            'Bạn có thể tiếp tục chỉnh sửa nội dung này bất kỳ lúc nào từ mục Bản nháp.',
            textAlign: TextAlign.center,
            style: ig.body(
              fontSize: 13,
              color: ig.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, DraftDiscardAction.saveDraft),
              style: ig.primaryButtonStyle(minHeight: 46, borderRadius: 12),
              child: const Text('Lưu bản nháp'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, DraftDiscardAction.discard),
              style: OutlinedButton.styleFrom(
                foregroundColor: ig.danger,
                side: BorderSide(color: ig.danger),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: ig.buttonLabel(color: ig.danger),
              ),
              child: const Text('Hủy bỏ thay đổi'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, DraftDiscardAction.cancel),
            child: Text(
              'Tiếp tục chỉnh sửa',
              style: ig.caption(fontSize: 13, color: ig.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
