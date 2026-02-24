import 'package:flutter_test/flutter_test.dart';
import 'package:roller_derby_jam_timer/models/game_config.dart';
import 'package:roller_derby_jam_timer/models/ruleset.dart';
import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';

void main() {
  // ─── Ruleset ────────────────────────────────────────────────────────────────

  group('Ruleset', () {
    group('WFTDA factory', () {
      late Ruleset ruleset;
      setUp(() => ruleset = Ruleset.wftda());

      test('has 2 periods of 30 minutes with 2-minute jams', () {
        expect(ruleset.periodCount, 2);
        expect(ruleset.periodDurationMs, 30 * 60 * 1000);
        expect(ruleset.jamDurationMs, 2 * 60 * 1000);
      });

      test('has 3 timeouts, 1 review per period, 30s lineup', () {
        expect(ruleset.timeoutsPerGame, 3);
        expect(ruleset.reviewsPerPeriod, 1);
        expect(ruleset.lineupDurationMs, 30 * 1000);
      });

      test('resets jam count each period', () {
        expect(ruleset.jamsResetPerPeriod, true);
      });

      test('has a single 15-minute intermission after period 1', () {
        expect(ruleset.intermissionDurationsMs, [15 * 60 * 1000]);
        expect(ruleset.getIntermissionDurationMs(1), 15 * 60 * 1000);
      });

      test('has no intermission after the final period', () {
        expect(ruleset.getIntermissionDurationMs(2), 0);
      });
    });

    group('RDCL factory', () {
      late Ruleset ruleset;
      setUp(() => ruleset = Ruleset.rdcl());

      test('has 4 periods of 15 minutes with 1-minute jams', () {
        expect(ruleset.periodCount, 4);
        expect(ruleset.periodDurationMs, 15 * 60 * 1000);
        expect(ruleset.jamDurationMs, 1 * 60 * 1000);
      });

      test('jam count continues across periods', () {
        expect(ruleset.jamsResetPerPeriod, false);
      });

      test('has three intermissions: 5min, 15min (halftime), 5min', () {
        expect(ruleset.getIntermissionDurationMs(1), 5 * 60 * 1000);
        expect(ruleset.getIntermissionDurationMs(2), 15 * 60 * 1000);
        expect(ruleset.getIntermissionDurationMs(3), 5 * 60 * 1000);
      });

      test('has no intermission after the final period', () {
        expect(ruleset.getIntermissionDurationMs(4), 0);
      });
    });

    group('getIntermissionDurationMs edge cases', () {
      test('returns 0 for period 0 or negative', () {
        final ruleset = Ruleset.wftda();
        expect(ruleset.getIntermissionDurationMs(0), 0);
        expect(ruleset.getIntermissionDurationMs(-1), 0);
      });

      test('falls back to first duration when index exceeds list', () {
        // Custom 5-period ruleset with only one intermission specified
        final ruleset = Ruleset.custom(
          id: 'test',
          name: 'Test',
          periodCount: 5,
          periodDurationMs: 10 * 60 * 1000,
          jamDurationMs: 60 * 1000,
          jamsResetPerPeriod: false,
          lineupDurationMs: 30 * 1000,
          lineupOvertimeDurationMs: 60 * 1000,
          timeoutsPerGame: 3,
          reviewsPerPeriod: 1,
          intermissionDurationsMs: [5 * 60 * 1000],
        );
        // Period 1, 2, 3, 4 all use the single specified duration
        expect(ruleset.getIntermissionDurationMs(1), 5 * 60 * 1000);
        expect(ruleset.getIntermissionDurationMs(2), 5 * 60 * 1000);
        expect(ruleset.getIntermissionDurationMs(3), 5 * 60 * 1000);
        expect(ruleset.getIntermissionDurationMs(4), 5 * 60 * 1000);
      });
    });

    group('JSON serialization', () {
      test('WFTDA ruleset round-trips through toJson/fromJson', () {
        final original = Ruleset.wftda();
        final restored = Ruleset.fromJson(original.toJson());

        expect(restored.id, original.id);
        expect(restored.name, original.name);
        expect(restored.isBuiltIn, original.isBuiltIn);
        expect(restored.periodCount, original.periodCount);
        expect(restored.periodDurationMs, original.periodDurationMs);
        expect(restored.jamDurationMs, original.jamDurationMs);
        expect(restored.jamsResetPerPeriod, original.jamsResetPerPeriod);
        expect(restored.lineupDurationMs, original.lineupDurationMs);
        expect(restored.lineupOvertimeDurationMs, original.lineupOvertimeDurationMs);
        expect(restored.timeoutsPerGame, original.timeoutsPerGame);
        expect(restored.reviewsPerPeriod, original.reviewsPerPeriod);
        expect(restored.intermissionDurationsMs, original.intermissionDurationsMs);
      });

      test('custom ruleset preserves all fields through JSON round-trip', () {
        final original = Ruleset.custom(
          id: 'my_ruleset',
          name: 'My Rules',
          periodCount: 3,
          periodDurationMs: 20 * 60 * 1000,
          jamDurationMs: 90 * 1000,
          jamsResetPerPeriod: true,
          lineupDurationMs: 25 * 1000,
          lineupOvertimeDurationMs: 45 * 1000,
          timeoutsPerGame: 2,
          reviewsPerPeriod: 2,
          intermissionDurationsMs: [10 * 60 * 1000, 15 * 60 * 1000],
        );
        final restored = Ruleset.fromJson(original.toJson());

        expect(restored.id, 'my_ruleset');
        expect(restored.name, 'My Rules');
        expect(restored.isBuiltIn, false);
        expect(restored.periodCount, 3);
        expect(restored.jamDurationMs, 90 * 1000);
        expect(restored.timeoutsPerGame, 2);
        expect(restored.reviewsPerPeriod, 2);
        expect(restored.intermissionDurationsMs, [10 * 60 * 1000, 15 * 60 * 1000]);
      });
    });

    group('copyWith', () {
      test('overrides only the specified fields', () {
        final base = Ruleset.wftda();
        final modified = base.copyWith(periodCount: 3, jamDurationMs: 90 * 1000);

        expect(modified.periodCount, 3);
        expect(modified.jamDurationMs, 90 * 1000);
        // Unchanged fields carry over
        expect(modified.periodDurationMs, base.periodDurationMs);
        expect(modified.name, base.name);
        expect(modified.timeoutsPerGame, base.timeoutsPerGame);
      });
    });
  });

  // ─── GameConfig ─────────────────────────────────────────────────────────────

  group('GameConfig', () {
    test('defaults to Salt and Pepper as team names', () {
      final config = GameConfig(ruleset: Ruleset.wftda());
      expect(config.team1Name, 'Salt');
      expect(config.team2Name, 'Pepper');
    });

    test('accepts custom team names', () {
      final config = GameConfig(
        ruleset: Ruleset.wftda(),
        team1Name: 'Thunder',
        team2Name: 'Lightning',
      );
      expect(config.team1Name, 'Thunder');
      expect(config.team2Name, 'Lightning');
    });

    test('round-trips through toJson/fromJson', () {
      final original = GameConfig(
        ruleset: Ruleset.rdcl(),
        team1Name: 'Red Devils',
        team2Name: 'Blue Angels',
      );
      final restored = GameConfig.fromJson(original.toJson());

      expect(restored.team1Name, 'Red Devils');
      expect(restored.team2Name, 'Blue Angels');
      expect(restored.ruleset.id, 'rdcl');
    });

    test('fromJson uses Salt/Pepper defaults when names are absent', () {
      final json = {
        'ruleset': Ruleset.wftda().toJson(),
        // team names intentionally omitted
      };
      final config = GameConfig.fromJson(json);
      expect(config.team1Name, 'Salt');
      expect(config.team2Name, 'Pepper');
    });

    test('copyWith overrides only specified fields', () {
      final original = GameConfig(ruleset: Ruleset.wftda(), team1Name: 'Alpha');
      final modified = original.copyWith(team1Name: 'Beta');

      expect(modified.team1Name, 'Beta');
      expect(modified.team2Name, original.team2Name);
      expect(modified.ruleset.id, original.ruleset.id);
    });
  });

  // ─── Team ───────────────────────────────────────────────────────────────────

  group('Team', () {
    test('displayName uses alternateName when it is set', () {
      final team = Team(id: '1', name: 'Thunder Cats', alternateName: 'TC');
      expect(team.displayName, 'TC');
    });

    test('displayName falls back to name when alternateName is empty', () {
      final team = Team(id: '1', name: 'Thunder Cats', alternateName: '');
      expect(team.displayName, 'Thunder Cats');
    });

    test('has sensible default values', () {
      final team = Team(id: '1');
      expect(team.name, 'Team');
      expect(team.score, 0);
      expect(team.timeouts, 3);
      expect(team.officialReviews, 1);
      expect(team.retainedOfficialReview, false);
    });
  });

  // ─── ScoreboardState ────────────────────────────────────────────────────────

  group('ScoreboardState', () {
    late ScoreboardState state;

    setUp(() => state = ScoreboardState());

    group('initial state', () {
      test('starts disconnected', () {
        expect(state.connectionStatus, 'Disconnected');
      });

      test('has all five clocks', () {
        expect(state.clocks.keys, containsAll(['Period', 'Jam', 'Lineup', 'Timeout', 'Intermission']));
      });

      test('game flags are all false', () {
        expect(state.inJam, false);
        expect(state.noMoreJam, false);
        expect(state.inOvertime, false);
        expect(state.injuryContinuationUpcoming, false);
      });
    });

    group('updateFromMap – game state flags', () {
      test('updates InJam', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.InJam': true});
        expect(state.inJam, true);

        state.updateFromMap({'ScoreBoard.CurrentGame.InJam': false});
        expect(state.inJam, false);
      });

      test('updates NoMoreJam', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.NoMoreJam': true});
        expect(state.noMoreJam, true);
      });

      test('updates InOvertime', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.InOvertime': true});
        expect(state.inOvertime, true);
      });

      test('updates InjuryContinuationUpcoming', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.InjuryContinuationUpcoming': true});
        expect(state.injuryContinuationUpcoming, true);
      });

      test('updates game ID', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Game': 'game-abc-123'});
        expect(state.gameId, 'game-abc-123');
      });

      test('updates TimeoutOwner', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.TimeoutOwner': 'team-uuid-1'});
        expect(state.timeoutOwner, 'team-uuid-1');
      });

      test('updates OfficialReview', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.OfficialReview': 'true'});
        expect(state.officialReview, 'true');
      });
    });

    group('updateFromMap – clocks', () {
      test('updates clock time', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Clock(Jam).Time': 90000});
        expect(state.clocks['Jam']!.time, 90000);
      });

      test('updates clock running state', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Clock(Period).Running': true});
        expect(state.clocks['Period']!.running, true);
      });

      test('updates clock number', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Clock(Period).Number': 2});
        expect(state.clocks['Period']!.number, 2);
      });

      test('updates clock display name', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Clock(Intermission).Name': 'Halftime'});
        expect(state.clocks['Intermission']!.displayName, 'Halftime');
      });

      test('handles numeric string for clock number', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Clock(Jam).Number': '5'});
        expect(state.clocks['Jam']!.number, 5);
      });

      test('ignores updates to unknown clocks', () {
        // Should not throw
        state.updateFromMap({'ScoreBoard.CurrentGame.Clock(UnknownClock).Time': 1000});
      });
    });

    group('updateFromMap – teams', () {
      test('updates team 1 score', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(1).Score': 42});
        expect(state.team1.score, 42);
      });

      test('updates team 2 score independently', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(2).Score': 17});
        expect(state.team2.score, 17);
        expect(state.team1.score, 0); // team 1 unchanged
      });

      test('updates team name', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(1).Name': 'Thunderbolts'});
        expect(state.team1.name, 'Thunderbolts');
      });

      test('updates team alternate name', () {
        state.updateFromMap({
          'ScoreBoard.CurrentGame.Team(1).AlternateName(Operator)': 'T-Bolts',
        });
        expect(state.team1.alternateName, 'T-Bolts');
      });

      test('updates team timeouts', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(1).Timeouts': 2});
        expect(state.team1.timeouts, 2);
      });

      test('updates team official reviews', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(2).OfficialReviews': 0});
        expect(state.team2.officialReviews, 0);
      });

      test('updates team retained official review', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(1).RetainedOfficialReview': true});
        expect(state.team1.retainedOfficialReview, true);
      });

      test('updates team server ID', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Team(2).Id': 'uuid-team-2'});
        expect(state.team2.serverId, 'uuid-team-2');
      });
    });

    group('updateFromMap – labels', () {
      test('updates Start label', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Label(Start)': 'Begin'});
        expect(state.labelStart, 'Begin');
      });

      test('updates Stop label', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Label(Stop)': 'End Jam'});
        expect(state.labelStop, 'End Jam');
      });

      test('updates Timeout label', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Label(Timeout)': 'Team TO'});
        expect(state.labelTimeout, 'Team TO');
      });

      test('updates Undo label', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Label(Undo)': 'UNDO: Start'});
        expect(state.labelUndo, 'UNDO: Start');
      });

      test('updates Replaced label', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Label(Replaced)': 'Replaced'});
        expect(state.labelReplaced, 'Replaced');
      });
    });

    group('updateFromMap – rules', () {
      test('updates lineup duration', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Rule(Lineup.Duration)': 25000});
        expect(state.lineupDuration, 25000);
      });

      test('updates lineup overtime duration', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Rule(Lineup.OvertimeDuration)': 45000});
        expect(state.lineupOvertimeDuration, 45000);
      });

      test('updates injury continuation rule', () {
        state.updateFromMap({'ScoreBoard.CurrentGame.Rule(Jam.InjuryContinuation)': true});
        expect(state.injuryContinuationRule, true);
      });
    });

    group('updateFromMap – batching', () {
      test('applies multiple updates and notifies listeners once', () {
        int notifyCount = 0;
        state.addListener(() => notifyCount++);

        state.updateFromMap({
          'ScoreBoard.CurrentGame.Team(1).Score': 10,
          'ScoreBoard.CurrentGame.Team(2).Score': 7,
          'ScoreBoard.CurrentGame.InJam': true,
          'ScoreBoard.CurrentGame.Clock(Jam).Running': true,
        });

        expect(state.team1.score, 10);
        expect(state.team2.score, 7);
        expect(state.inJam, true);
        expect(state.clocks['Jam']!.running, true);
        expect(notifyCount, 1); // Single notification for the whole batch
      });
    });

    group('setConnectionStatus', () {
      test('notifies listeners on change', () {
        int notifyCount = 0;
        state.addListener(() => notifyCount++);
        state.setConnectionStatus('Connected');
        expect(state.connectionStatus, 'Connected');
        expect(notifyCount, 1);
      });
    });

    group('notify', () {
      test('notifies listeners when called directly', () {
        int notifyCount = 0;
        state.addListener(() => notifyCount++);
        state.notify();
        expect(notifyCount, 1);
      });
    });
  });
}
