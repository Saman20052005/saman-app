import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';

import '../tool/export_ai_exercise_catalog.dart';

void main() {
  test('Library provider returns the catalog exported by the tool', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final provided = await container.read(exerciseLibraryListProvider.future);
    expect(identical(provided, curatedExerciseLibrary), isTrue);

    final artifact = buildExerciseCatalogArtifact(provided);
    final records = artifact['exercises'] as List<Map<String, dynamic>>;
    expect(records.length, provided.length);
    expect(
      records,
      provided.map((exercise) => exercise.toJson()).toList(),
    );

    final ids = records.map((record) => record['id']).toList();
    final slugs = records
        .map((record) => (record['slug'] as String).toLowerCase())
        .toList();
    expect(ids.every((id) => id is String && id.isNotEmpty), isTrue);
    expect(slugs.every((slug) => slug.isNotEmpty), isTrue);
    expect(ids.toSet().length, ids.length);
    expect(slugs.toSet().length, slugs.length);
    expect(artifact['schema_version'], 1);
    expect(artifact['generated'], isTrue);
    expect(
      artifact['generator'],
      'frontend/tool/export_ai_exercise_catalog.dart',
    );
    expect(artifact['source_sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      records.first,
      containsPair('thumbnailUrl', curatedExerciseLibrary.first.thumbnailUrl),
    );
    expect(
      records.first,
      containsPair('cvSupported', curatedExerciseLibrary.first.cvSupported),
    );

    final actualArtifact = File(
      '../backend/app/data/ai_exercise_catalog.generated.json',
    );
    expect(
      utf8.decode(actualArtifact.readAsBytesSync()),
      encodeExerciseCatalog(provided),
    );
  });

  test('catalog output is byte deterministic and check mode never writes', () {
    final expected = encodeExerciseCatalog(curatedExerciseLibrary);
    expect(encodeExerciseCatalog(curatedExerciseLibrary), expected);

    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'ai-exercise-catalog-',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final output = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}catalog.json',
    );
    output.writeAsStringSync('stale artifact', encoding: utf8);
    final before = output.readAsBytesSync();

    expect(runExerciseCatalogExporter(['--check'], output: output), 1);
    expect(output.readAsBytesSync(), before);
  });

  test('check mode rejects a missing artifact without creating it', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'ai-exercise-catalog-missing-',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final output = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}missing.json',
    );

    expect(runExerciseCatalogExporter(['--check'], output: output), 1);
    expect(output.existsSync(), isFalse);
  });

  test('duplicate IDs, duplicate slugs, and empty identities fail before write',
      () {
    final first = curatedExerciseLibrary.first;
    final second = curatedExerciseLibrary[1];
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'ai-exercise-catalog-invalid-',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));

    final duplicateId = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}duplicate-id.json',
    );
    expect(
      () => exportExerciseCatalog(
        exercises: [first, second.copyWith(id: first.id)],
        output: duplicateId,
      ),
      throwsFormatException,
    );
    expect(duplicateId.existsSync(), isFalse);

    final duplicateSlug = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}duplicate-slug.json',
    );
    expect(
      () => exportExerciseCatalog(
        exercises: [first, second.copyWith(slug: first.slug.toUpperCase())],
        output: duplicateSlug,
      ),
      throwsFormatException,
    );
    expect(duplicateSlug.existsSync(), isFalse);

    final emptyIdentity = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}empty-id.json',
    );
    expect(
      () => exportExerciseCatalog(
        exercises: [first.copyWith(id: '')],
        output: emptyIdentity,
      ),
      throwsFormatException,
    );
    expect(emptyIdentity.existsSync(), isFalse);

    final syntheticId = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}synthetic-id.json',
    );
    expect(
      () => exportExerciseCatalog(
        exercises: [first.copyWith(id: 'plan_ex_0')],
        output: syntheticId,
      ),
      throwsFormatException,
    );
    expect(syntheticId.existsSync(), isFalse);
  });
}
