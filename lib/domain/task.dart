enum TaskKind { oneOff, recurring }

enum TaskStatus { active, benched, archived, removed }

class Task {
  final String id;
  final String title;
  final TaskKind kind;
  final int? intervalDays;
  final DateTime? dueAt;
  final DateTime createdAt;
  final DateTime? completedAt;
  final TaskStatus status;

  Task({
    required this.id,
    required this.title,
    required this.kind,
    this.intervalDays,
    this.dueAt,
    required this.createdAt,
    this.completedAt,
    this.status = TaskStatus.active,
  })  : assert(
          kind != TaskKind.recurring ||
              (intervalDays != null && intervalDays > 0),
          'recurring tasks need a positive intervalDays',
        ),
        assert(
          kind != TaskKind.oneOff || intervalDays == null,
          'one-off tasks must not have intervalDays',
        );

  Task copyWith({
    String? id,
    String? title,
    TaskKind? kind,
    int? intervalDays,
    DateTime? dueAt,
    DateTime? createdAt,
    DateTime? completedAt,
    TaskStatus? status,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      intervalDays: intervalDays ?? this.intervalDays,
      dueAt: dueAt ?? this.dueAt,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.intervalDays == intervalDays &&
      other.dueAt == dueAt &&
      other.createdAt == createdAt &&
      other.completedAt == completedAt &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
        id, title, kind, intervalDays, dueAt, createdAt, completedAt, status,
      );
}
