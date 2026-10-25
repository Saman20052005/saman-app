import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures/chat_render/render_resources.dart';

void main() {
  late Directory fonts;

  setUp(() {
    fonts = Directory.systemTemp.createTempSync('saman_render_fonts_');
  });

  tearDown(() {
    fonts.deleteSync(recursive: true);
  });

  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
    'MaterialIcons-Regular.otf',
  ]) {
    for (final lowercase in [false, true]) {
      test('Reads $name from ${lowercase ? 'lowercase cache' : 'SDK archive'}',
          () async {
        final filename = lowercase ? name.toLowerCase() : name;
        final file = File.fromUri(fonts.uri.resolve(filename));
        await file.writeAsBytes([1, 2, 3, 4]);
        expect(fonts.listSync().map((entry) => entry.uri.pathSegments.last),
            [filename]);

        final data = await readChatRenderFont(fonts, name);

        expect(data.buffer.asUint8List(), [1, 2, 3, 4]);
      });
    }
  }

  test('Missing font fails with every candidate path instead of a substitute',
      () async {
    await File.fromUri(fonts.uri.resolve('WorkSans-Regular.ttf'))
        .writeAsBytes([1, 2, 3, 4]);
    const name = 'Roboto-Regular.ttf';

    await expectLater(
      readChatRenderFont(fonts, name),
      throwsA(isA<FileSystemException>()
          .having((error) => error.path, 'font directory', fonts.path)
          .having(
              (error) => error.message,
              'attempted candidates',
              allOf(
                  contains('Missing render font $name'),
                  contains(File.fromUri(fonts.uri.resolve(name)).path),
                  contains(File.fromUri(fonts.uri.resolve(name.toLowerCase()))
                      .path)))),
    );
  });
}
