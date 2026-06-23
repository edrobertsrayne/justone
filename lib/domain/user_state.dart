class UserState {
  // --- config ---
  final String timezone;
  final int target;
  final List<String> remindersWeekday;
  final List<String> remindersWeekend;
  final bool onboardingComplete;

  // --- progress ---
  final int streak;
  final int bestStreak;
  final int targetMetDays;
  final int lifetimeDone;

  // --- today (reset client-side per D7) ---
  final bool bankedToday;
  final bool targetDismissed;
  final int doneToday;
  final int rerolls;
  final DateTime lastActiveDate;

  const UserState({
    required this.timezone,
    this.target = 3,
    this.remindersWeekday = const [],
    this.remindersWeekend = const [],
    this.onboardingComplete = false,
    this.streak = 0,
    this.bestStreak = 0,
    this.targetMetDays = 0,
    this.lifetimeDone = 0,
    this.bankedToday = false,
    this.targetDismissed = false,
    this.doneToday = 0,
    this.rerolls = 3,
    required this.lastActiveDate,
  });

  UserState copyWith({
    String? timezone,
    int? target,
    List<String>? remindersWeekday,
    List<String>? remindersWeekend,
    bool? onboardingComplete,
    int? streak,
    int? bestStreak,
    int? targetMetDays,
    int? lifetimeDone,
    bool? bankedToday,
    bool? targetDismissed,
    int? doneToday,
    int? rerolls,
    DateTime? lastActiveDate,
  }) {
    return UserState(
      timezone: timezone ?? this.timezone,
      target: target ?? this.target,
      remindersWeekday: remindersWeekday ?? this.remindersWeekday,
      remindersWeekend: remindersWeekend ?? this.remindersWeekend,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      streak: streak ?? this.streak,
      bestStreak: bestStreak ?? this.bestStreak,
      targetMetDays: targetMetDays ?? this.targetMetDays,
      lifetimeDone: lifetimeDone ?? this.lifetimeDone,
      bankedToday: bankedToday ?? this.bankedToday,
      targetDismissed: targetDismissed ?? this.targetDismissed,
      doneToday: doneToday ?? this.doneToday,
      rerolls: rerolls ?? this.rerolls,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is UserState &&
      other.timezone == timezone &&
      other.target == target &&
      _listEq(other.remindersWeekday, remindersWeekday) &&
      _listEq(other.remindersWeekend, remindersWeekend) &&
      other.onboardingComplete == onboardingComplete &&
      other.streak == streak &&
      other.bestStreak == bestStreak &&
      other.targetMetDays == targetMetDays &&
      other.lifetimeDone == lifetimeDone &&
      other.bankedToday == bankedToday &&
      other.targetDismissed == targetDismissed &&
      other.doneToday == doneToday &&
      other.rerolls == rerolls &&
      other.lastActiveDate == lastActiveDate;

  @override
  int get hashCode => Object.hash(
        timezone,
        target,
        Object.hashAll(remindersWeekday),
        Object.hashAll(remindersWeekend),
        onboardingComplete,
        streak,
        bestStreak,
        targetMetDays,
        lifetimeDone,
        bankedToday,
        targetDismissed,
        doneToday,
        rerolls,
        lastActiveDate,
      );
}
