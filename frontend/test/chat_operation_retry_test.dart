import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/controllers/chat_controller.dart';

void main() {
  test('operation ids contain 128 bits of cryptographically secure entropy', () {
    final first = generateChatOperationId();
    final second = generateChatOperationId();
    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second, isNot(first));
  });
}
