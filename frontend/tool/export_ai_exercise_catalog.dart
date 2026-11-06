import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:health_ai_app/data/models/exercise.dart';
import 'package:health_ai_app/presentation/providers/exercise_providers.dart';

const _schemaVersion = 1;
const _generator = 'frontend/tool/export_ai_exercise_catalog.dart';
const _source = 'frontend/lib/presentation/providers/exercise_providers.dart:'
    'curatedExerciseLibrary';
const _exerciseFields = <String>[
  'id',
  'slug',
  'name',
  'nameVi',
  'muscleGroup',
  'targetMuscles',
  'secondaryMuscles',
  'equipment',
  'difficulty',
  'thumbnailUrl',
  'youtubeVideoId',
  'cues',
  'commonMistakes',
  'defaultSets',
  'defaultReps',
  'restSeconds',
  'repType',
  'cvSupported',
  'cvModuleId',
];

Map<String, dynamic> buildExerciseCatalogArtifact(
  Iterable<Exercise> exercises,
) {
  final records = <Map<String, dynamic>>[];
  final ids = <String>{};
  final slugs = <String>{};

  for (final exercise in exercises) {
    final serialized = exercise.toJson();
    if (serialized.keys
            .toSet()
            .difference(_exerciseFields.toSet())
            .isNotEmpty ||
        _exerciseFields
            .toSet()
            .difference(serialized.keys.toSet())
            .isNotEmpty) {
      throw const FormatException(
        'Exercise serialization does not match the catalog schema.',
      );
    }

    final record = <String, dynamic>{
      for (final field in _exerciseFields) field: serialized[field],
    };
    _validateRecord(record);

    final id = record['id'] as String;
    final slug = record['slug'] as String;
    if (id.startsWith('plan_ex_')) {
      throw FormatException('Synthetic plan ID cannot be canonical: $id');
    }
    if (!ids.add(id)) {
      throw FormatException('Duplicate exercise ID: $id');
    }
    if (!slugs.add(slug.toLowerCase())) {
      throw FormatException('Duplicate normalized exercise slug: $slug');
    }
    records.add(record);
  }

  if (records.isEmpty) {
    throw const FormatException('The Library exercise catalog is empty.');
  }

  final sourceBytes = utf8.encode(jsonEncode(records));
  return <String, dynamic>{
    'schema_version': _schemaVersion,
    'generated': true,
    'generator': _generator,
    'source': _source,
    'source_sha256': sha256.convert(sourceBytes).toString(),
    'exercises': records,
  };
}

String encodeExerciseCatalog(Iterable<Exercise> exercises) {
  final artifact = buildExerciseCatalogArtifact(exercises);
  return '${const JsonEncoder.withIndent('  ').convert(artifact)}\n';
}

void exportExerciseCatalog({
  required Iterable<Exercise> exercises,
  required File output,
  bool check = false,
}) {
  final generated = encodeExerciseCatalog(exercises);
  if (check) {
    if (!output.existsSync() ||
        utf8.decode(output.readAsBytesSync()) != generated) {
      throw StateError('Generated exercise catalog is missing or stale.');
    }
    return;
  }

  output.parent.createSync(recursive: true);
  output.writeAsStringSync(generated, encoding: utf8, flush: true);
}

void _validateRecord(Map<String, dynamic> record) {
  const nonEmptyStrings = <String>[
    'id',
    'slug',
    'name',
    'nameVi',
    'muscleGroup',
    'difficulty',
    'thumbnailUrl',
    'defaultReps',
    'repType',
  ];
  for (final field in nonEmptyStrings) {
    final value = record[field];
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw FormatException('Invalid required exercise field: $field');
    }
  }

  for (final field in <String>['youtubeVideoId', 'cvModuleId']) {
    final value = record[field];
    if (value != null && (value is! String || value.trim().isEmpty)) {
      throw FormatException('Invalid optional exercise field: $field');
    }
  }

  for (final field in <String>[
    'targetMuscles',
    'secondaryMuscles',
    'equipment',
    'cues',
    'commonMistakes',
  ]) {
    final value = record[field];
    if (value is! List ||
        value.any((item) => item is! String || item.trim().isEmpty)) {
      throw FormatException('Invalid exercise list field: $field');
    }
  }

  if (record['defaultSets'] is! int ||
      (record['defaultSets'] as int) < 1 ||
      record['restSeconds'] is! int ||
      (record['restSeconds'] as int) < 0 ||
      record['cvSupported'] is! bool) {
    throw const FormatException('Invalid numeric or boolean exercise field.');
  }

  final thumbnail = record['thumbnailUrl'] as String;
  if (thumbnail.startsWith('/') ||
      thumbnail.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(thumbnail)) {
    throw const FormatException(
      'Absolute machine-specific thumbnail paths are not allowed.',
    );
  }
}

File _artifactFile() {
  final script = File.fromUri(Platform.script).absolute;
  final repositoryRoot = script.parent.parent.parent;
  return File(
    '${repositoryRoot.path}${Platform.pathSeparator}backend'
    '${Platform.pathSeparator}app${Platform.pathSeparator}data'
    '${Platform.pathSeparator}ai_exercise_catalog.generated.json',
  );
}

int runExerciseCatalogExporter(
  List<String> arguments, {
  File? output,
}) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln(
        'Usage: dart run tool/export_ai_exercise_catalog.dart [--check]');
    return 2;
  }

  try {
    exportExerciseCatalog(
      exercises: curatedExerciseLibrary,
      output: output ?? _artifactFile(),
      check: arguments.contains('--check'),
    );
    stdout.writeln(
      arguments.contains('--check')
          ? 'Generated exercise catalog is current.'
          : 'Generated exercise catalog.',
    );
    return 0;
  } on FormatException catch (error) {
    stderr.writeln('Exercise catalog export failed: ${error.message}');
    return 1;
  } on FileSystemException catch (error) {
    stderr.writeln('Exercise catalog export failed: ${error.message}');
    return 1;
  } on StateError catch (error) {
    stderr.writeln('Exercise catalog check failed: ${error.message}');
    return 1;
  }
}

void main(List<String> arguments) {
  exitCode = runExerciseCatalogExporter(arguments);
}
