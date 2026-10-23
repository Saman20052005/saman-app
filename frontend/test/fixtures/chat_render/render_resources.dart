import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

/// Loads real glyphs explicitly because flutter test disables asset fonts.
Future<void> loadChatRenderFonts() async {
  final packageConfig = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await packageConfig.readAsString()) as Map<String, dynamic>;
  final flutterPackage = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final flutterRoot = Directory.fromUri(
    packageConfig.uri.resolve(flutterPackage['rootUri'] as String),
  );
  final sdkRoot = flutterRoot.parent.parent;
  final fontDirectory = Directory.fromUri(
    sdkRoot.uri.resolve('bin/cache/artifacts/material_fonts/'),
  );

  Future<ByteData> readFont(String name) async {
    final bytes =
        await File.fromUri(fontDirectory.uri.resolve(name)).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  final textFont = FontLoader('Roboto');
  for (final name in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
  ]) {
    textFont.addFont(readFont(name));
  }
  await textFont.load();

  final iconFont = FontLoader('MaterialIcons')
    ..addFont(readFont('materialicons-regular.otf'));
  await iconFont.load();
}

/// SDK Roboto lacks U+2192 used by the production Retry text.
Future<void> loadChatRenderSymbolFont() async {
  final bytes = await File('test/fixtures/chat_render/WorkSans-Regular.ttf')
      .readAsBytes();
  final symbols = FontLoader('ChatRenderSymbols')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await symbols.load();
}

/// Decodes before pumpWidget starts an image request in the test's fake clock.
Future<void> cacheChatRenderPhoto(String path) async {
  final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
  final ready = Completer<void>();
  final listener = ImageStreamListener(
    (_, __) => ready.complete(),
    onError: ready.completeError,
  );
  stream.addListener(listener);
  try {
    await ready.future;
  } finally {
    stream.removeListener(listener);
  }
}
