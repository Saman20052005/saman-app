class MuscleGroup {
  final int id;
  final String name;
  final String nameVi;
  final String slug;
  final String description;
  final String icon;
  final String color;
  final int exerciseCount;

  const MuscleGroup({
    required this.id,
    required this.name,
    required this.nameVi,
    required this.slug,
    required this.description,
    required this.icon,
    required this.color,
    required this.exerciseCount,
  });

  factory MuscleGroup.fromJson(Map<String, dynamic> json) {
    return MuscleGroup(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      nameVi: json['name_vi'] as String? ?? json['nameVi'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'fitness_center',
      color: json['color'] as String? ?? '#FF6B6B',
      exerciseCount:
          json['exercise_count'] as int? ?? json['exerciseCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'nameVi': nameVi,
      'slug': slug,
      'description': description,
      'icon': icon,
      'color': color,
      'exerciseCount': exerciseCount,
    };
  }

  MuscleGroup copyWith({
    int? id,
    String? name,
    String? nameVi,
    String? slug,
    String? description,
    String? icon,
    String? color,
    int? exerciseCount,
  }) {
    return MuscleGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      nameVi: nameVi ?? this.nameVi,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      exerciseCount: exerciseCount ?? this.exerciseCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MuscleGroup && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MuscleGroup{id: $id, name: $name, nameVi: $nameVi, slug: $slug}';
  }
}
