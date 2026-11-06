import 'package:flutter/material.dart';
import '../../../../screens/home/tokens/saman_home_tokens.dart';

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
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              color: const Color(0xFF343536),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Lưu bản nháp bài viết?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: SamanHomeTokens.textWhite,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bạn có thể tiếp tục chỉnh sửa nội dung này bất kỳ lúc nào từ mục Bản nháp.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFFBBCAAF),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: SamanHomeTokens.greenAccent,
                foregroundColor: const Color(0xFF003824),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Lưu bản nháp',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                foregroundColor: const Color(0xFFFFB4AB),
                side: const BorderSide(color: Color(0xFF93000A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Hủy bỏ thay đổi',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, DraftDiscardAction.cancel),
            child: const Text(
              'Tiếp tục chỉnh sửa',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFBBCAAF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
