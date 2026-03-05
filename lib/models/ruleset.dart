/// Represents a game ruleset defining timing and period rules.
class Ruleset {
  final String id;
  final String name;
  final bool isBuiltIn;
  final int periodCount;
  final int periodDurationMs;
  final int jamDurationMs;
  final bool jamsResetPerPeriod;
  final int lineupDurationMs;
  final int lineupOvertimeDurationMs;
  final int timeoutsPerPeriod;
  final int reviewsPerPeriod;
  final List<int> intermissionDurationsMs;

  const Ruleset({
    required this.id,
    required this.name,
    required this.isBuiltIn,
    required this.periodCount,
    required this.periodDurationMs,
    required this.jamDurationMs,
    required this.jamsResetPerPeriod,
    required this.lineupDurationMs,
    required this.lineupOvertimeDurationMs,
    required this.timeoutsPerPeriod,
    required this.reviewsPerPeriod,
    required this.intermissionDurationsMs,
  });

  /// WFTDA ruleset: 2 x 30min periods, 2min jams
  factory Ruleset.wftda() => const Ruleset(
        id: 'wftda',
        name: 'WFTDA',
        isBuiltIn: true,
        periodCount: 2,
        periodDurationMs: 30 * 60 * 1000, // 30 minutes
        jamDurationMs: 2 * 60 * 1000, // 2 minutes
        jamsResetPerPeriod: true,
        lineupDurationMs: 30 * 1000, // 30 seconds
        lineupOvertimeDurationMs: 60 * 1000, // 1 minute
        timeoutsPerPeriod: 3,
        reviewsPerPeriod: 1,
        intermissionDurationsMs: [15 * 60 * 1000], // 15 min intermission
      );

  /// RDCL ruleset: 4 x 15min periods, 1min jams
  factory Ruleset.rdcl() => const Ruleset(
        id: 'rdcl',
        name: 'RDCL',
        isBuiltIn: true,
        periodCount: 4,
        periodDurationMs: 15 * 60 * 1000, // 15 minutes
        jamDurationMs: 1 * 60 * 1000, // 1 minute
        jamsResetPerPeriod: false,
        lineupDurationMs: 30 * 1000, // 30 seconds
        lineupOvertimeDurationMs: 60 * 1000, // 1 minute
        timeoutsPerPeriod: 3,
        reviewsPerPeriod: 1,
        intermissionDurationsMs: [
          5 * 60 * 1000, // 5 min after period 1
          15 * 60 * 1000, // 15 min halftime
          5 * 60 * 1000, // 5 min after period 3
        ],
      );

  /// Create a custom ruleset with a unique ID
  factory Ruleset.custom({
    required String id,
    required String name,
    required int periodCount,
    required int periodDurationMs,
    required int jamDurationMs,
    required bool jamsResetPerPeriod,
    required int lineupDurationMs,
    required int lineupOvertimeDurationMs,
    required int timeoutsPerPeriod,
    required int reviewsPerPeriod,
    required List<int> intermissionDurationsMs,
  }) =>
      Ruleset(
        id: id,
        name: name,
        isBuiltIn: false,
        periodCount: periodCount,
        periodDurationMs: periodDurationMs,
        jamDurationMs: jamDurationMs,
        jamsResetPerPeriod: jamsResetPerPeriod,
        lineupDurationMs: lineupDurationMs,
        lineupOvertimeDurationMs: lineupOvertimeDurationMs,
        timeoutsPerPeriod: timeoutsPerPeriod,
        reviewsPerPeriod: reviewsPerPeriod,
        intermissionDurationsMs: intermissionDurationsMs,
      );

  /// Get the intermission duration after a specific period (1-indexed)
  int getIntermissionDurationMs(int afterPeriod) {
    if (afterPeriod <= 0 || afterPeriod >= periodCount) return 0;
    final index = afterPeriod - 1;
    if (index < intermissionDurationsMs.length) {
      return intermissionDurationsMs[index];
    }
    // Default to first intermission duration if not specified
    return intermissionDurationsMs.isNotEmpty
        ? intermissionDurationsMs.first
        : 15 * 60 * 1000;
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isBuiltIn': isBuiltIn,
        'periodCount': periodCount,
        'periodDurationMs': periodDurationMs,
        'jamDurationMs': jamDurationMs,
        'jamsResetPerPeriod': jamsResetPerPeriod,
        'lineupDurationMs': lineupDurationMs,
        'lineupOvertimeDurationMs': lineupOvertimeDurationMs,
        'timeoutsPerPeriod': timeoutsPerPeriod,
        'reviewsPerPeriod': reviewsPerPeriod,
        'intermissionDurationsMs': intermissionDurationsMs,
      };

  /// Create from JSON
  factory Ruleset.fromJson(Map<String, dynamic> json) => Ruleset(
        id: json['id'] as String,
        name: json['name'] as String,
        isBuiltIn: json['isBuiltIn'] as bool,
        periodCount: json['periodCount'] as int,
        periodDurationMs: json['periodDurationMs'] as int,
        jamDurationMs: json['jamDurationMs'] as int,
        jamsResetPerPeriod: json['jamsResetPerPeriod'] as bool,
        lineupDurationMs: json['lineupDurationMs'] as int,
        lineupOvertimeDurationMs: json['lineupOvertimeDurationMs'] as int,
        timeoutsPerPeriod: (json['timeoutsPerPeriod'] ?? json['timeoutsPerGame'] ?? 3) as int,
        reviewsPerPeriod: json['reviewsPerPeriod'] as int,
        intermissionDurationsMs:
            (json['intermissionDurationsMs'] as List).cast<int>(),
      );

  Ruleset copyWith({
    String? id,
    String? name,
    bool? isBuiltIn,
    int? periodCount,
    int? periodDurationMs,
    int? jamDurationMs,
    bool? jamsResetPerPeriod,
    int? lineupDurationMs,
    int? lineupOvertimeDurationMs,
    int? timeoutsPerPeriod,
    int? reviewsPerPeriod,
    List<int>? intermissionDurationsMs,
  }) =>
      Ruleset(
        id: id ?? this.id,
        name: name ?? this.name,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
        periodCount: periodCount ?? this.periodCount,
        periodDurationMs: periodDurationMs ?? this.periodDurationMs,
        jamDurationMs: jamDurationMs ?? this.jamDurationMs,
        jamsResetPerPeriod: jamsResetPerPeriod ?? this.jamsResetPerPeriod,
        lineupDurationMs: lineupDurationMs ?? this.lineupDurationMs,
        lineupOvertimeDurationMs:
            lineupOvertimeDurationMs ?? this.lineupOvertimeDurationMs,
        timeoutsPerPeriod: timeoutsPerPeriod ?? this.timeoutsPerPeriod,
        reviewsPerPeriod: reviewsPerPeriod ?? this.reviewsPerPeriod,
        intermissionDurationsMs:
            intermissionDurationsMs ?? this.intermissionDurationsMs,
      );
}
