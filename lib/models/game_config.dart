import 'ruleset.dart';

/// Configuration for starting a new offline game.
class GameConfig {
  final Ruleset ruleset;
  final String team1Name;
  final String team2Name;

  const GameConfig({
    required this.ruleset,
    this.team1Name = 'Salt',
    this.team2Name = 'Pepper',
  });

  GameConfig copyWith({
    Ruleset? ruleset,
    String? team1Name,
    String? team2Name,
  }) => GameConfig(
    ruleset: ruleset ?? this.ruleset,
    team1Name: team1Name ?? this.team1Name,
    team2Name: team2Name ?? this.team2Name,
  );

  Map<String, dynamic> toJson() => {
    'ruleset': ruleset.toJson(),
    'team1Name': team1Name,
    'team2Name': team2Name,
  };

  factory GameConfig.fromJson(Map<String, dynamic> json) => GameConfig(
    ruleset: Ruleset.fromJson(json['ruleset'] as Map<String, dynamic>),
    team1Name: json['team1Name'] as String? ?? 'Salt',
    team2Name: json['team2Name'] as String? ?? 'Pepper',
  );
}
