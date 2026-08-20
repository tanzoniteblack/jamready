import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/services/local_penalty_engine.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<LocalPenaltyEngine> startEngine(PenaltyBoxState state) async {
    final engine = LocalPenaltyEngine(state);
    await engine.initialize();
    return engine;
  }

  // ---------------------------------------------------------------------------
  // initialize()
  // ---------------------------------------------------------------------------

  group('initialize()', () {
    test('starts in jam-running state with jamNumber=1', () async {
      final state = makeState();
      await startEngine(state);

      expect(state.jamRunning, isTrue);
      expect(state.jamNumber, 1);
    });

    test('loads known numbers from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'jambox_known_t1': ['10', '42'],
        'jambox_known_t2': ['99'],
      });

      final state = makeState();
      await startEngine(state);

      expect(state.knownNumbers(1), containsAll(['10', '42']));
      expect(state.knownNumbers(2), contains('99'));
    });

    test('works cleanly with empty SharedPreferences', () async {
      final state = makeState();
      await startEngine(state); // should not throw
      expect(state.knownNumbers(1), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // toggleJam()
  // ---------------------------------------------------------------------------

  group('toggleJam()', () {
    test('running → stopped', () async {
      final state = makeState();
      await startEngine(state);
      expect(state.jamRunning, isTrue);

      final engine = LocalPenaltyEngine(state);
      await engine.initialize();
      engine.toggleJam();

      expect(state.jamRunning, isFalse);
    });

    test('stopped → running, increments jamNumber', () async {
      final state = makeState();
      final engine = await startEngine(state);
      engine.toggleJam(); // stop jam 1
      final jamBefore = state.jamNumber;

      engine.toggleJam(); // start jam 2

      expect(state.jamRunning, isTrue);
      expect(state.jamNumber, jamBefore + 1);
    });

    test('multiple toggles cycle correctly', () async {
      final state = makeState();
      final engine = await startEngine(state);

      engine.toggleJam();
      expect(state.jamRunning, isFalse);
      engine.toggleJam();
      expect(state.jamRunning, isTrue);
      engine.toggleJam();
      expect(state.jamRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Timer tick via fake_async
  // ---------------------------------------------------------------------------

  group('Timer tick', () {
    test(
      'jammer swap applies WFTDA arrival timing while the local engine runs',
      () async {
        final state = makeState();
        final engine = await startEngine(state);

        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 10));
        seatJammer(state, 2, '20');

        expectTimeRemaining(state.team1Jammer, Duration.zero);
        expectTimeRemaining(state.team2Jammer, const Duration(seconds: 10));
        expect(state.team1Jammer.isRunning, isFalse);
        expect(state.team2Jammer.isRunning, isTrue);

        await engine.dispose();
      },
    );

    test('running seat loses time after 100ms tick', () {
      final state = makeState();

      fakeAsync((fake) {
        state.jamRunning = true;
        state.jamNumber = 1;

        // Inject a clock that uses fake_async's fake time.
        final engine = LocalPenaltyEngine(
          state,
          clock: () => fake.getClock(DateTime(2024)).now(),
        );
        engine.startTicker();

        state.seatSkater(
          seat: state.team1Jammer,
          number: '10',
          position: SkaterPosition.jammer,
        );
        state.team1Jammer.isRunning = true;

        fake.elapse(const Duration(milliseconds: 100));

        expect(
          state.team1Jammer.timeRemaining,
          lessThan(const Duration(seconds: 30)),
        );
      });
    });

    test('paused seat is unaffected by timer ticks', () {
      final state = makeState();

      fakeAsync((fake) {
        state.jamRunning = false;
        final engine = LocalPenaltyEngine(
          state,
          clock: () => fake.getClock(DateTime(2024)).now(),
        );
        engine.startTicker();

        state.seatSkater(
          seat: state.team1Blocker1,
          number: '22',
          position: SkaterPosition.blocker,
        );
        state.team1Blocker1.isRunning = false;

        fake.elapse(const Duration(seconds: 5));

        expect(state.team1Blocker1.timeRemaining, const Duration(seconds: 30));
      });
    });

    test('seat reaches zero after sufficient ticks', () {
      final state = makeState();

      fakeAsync((fake) {
        state.jamRunning = true;
        final engine = LocalPenaltyEngine(
          state,
          clock: () => fake.getClock(DateTime(2024)).now(),
        );
        engine.startTicker();

        state.seatSkater(
          seat: state.team1Jammer,
          number: '10',
          position: SkaterPosition.jammer,
        );
        state.team1Jammer.isRunning = true;

        fake.elapse(const Duration(seconds: 31));

        expect(state.team1Jammer.timeRemaining, Duration.zero);
        expect(state.team1Jammer.isRunning, isFalse);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Jammer Swaps Visualised (WFTDA §4.4.2)
  // ---------------------------------------------------------------------------

  group('Jammer Swaps Visualised', () {
    Future<PenaltyBoxState> runningState() async {
      final state = makeState();
      final engine = await startEngine(state);
      addTearDown(engine.dispose);
      return state;
    }

    test('Scenario 1: one jammer serves a normal penalty', () async {
      final state = await runningState();
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 10));

      expectTimeRemaining(state.team1Jammer, const Duration(seconds: 20));
    });

    test('Scenario 2: one-for-one jammer swap', () async {
      final state = await runningState();
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 20));
      seatJammer(state, 2, '20');

      expectJammerTimes(
        state,
        team1: Duration.zero,
        team2: const Duration(seconds: 20),
      );
    });

    test('Scenario 3: completed penalty is not paired again', () async {
      final state = await runningState();
      seatJammer(state, 1, '10', penalties: 2);
      state.tick(const Duration(seconds: 45));
      seatJammer(state, 2, '20');

      expectJammerTimes(
        state,
        team1: Duration.zero,
        team2: const Duration(seconds: 15),
      );
    });

    test('Scenario 4: a later penalty can be fully cancelled', () async {
      final state = await runningState();
      seatJammer(state, 1, '10', penalties: 2);
      state.tick(const Duration(seconds: 15));
      seatJammer(state, 2, '20');

      expectJammerTimes(
        state,
        team1: const Duration(seconds: 15),
        team2: Duration.zero,
      );
    });

    test('Scenario 5: simultaneous jammer penalties release both', () async {
      final state = await runningState();
      seatJammer(state, 1, '10');
      seatJammer(state, 2, '20');

      expectJammerTimes(state, team1: Duration.zero, team2: Duration.zero);
    });

    test('Scenario 6: a new penalty is not paired with settled time', () async {
      final state = await runningState();
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 15));
      seatJammer(state, 2, '20');
      state.clearSeat(state.team1Jammer);
      seatJammer(state, 1, '11');

      expectJammerTimes(
        state,
        team1: const Duration(seconds: 30),
        team2: const Duration(seconds: 15),
      );
    });

    test('Scenario 7: an extra arriving penalty remains unpaired', () async {
      final state = await runningState();
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 15));
      seatJammer(state, 2, '20', penalties: 2);

      expectJammerTimes(
        state,
        team1: Duration.zero,
        team2: const Duration(seconds: 45),
      );
      expect(state.team2Jammer.unmatchedPenalties, 1);
    });

    test(
      'Scenario 8: a second unmatched penalty supports a second swap',
      () async {
        final state = await runningState();
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 15));
        seatJammer(state, 2, '20', penalties: 2);
        state.clearSeat(state.team1Jammer);
        state.tick(const Duration(seconds: 30));
        seatJammer(state, 1, '11');

        expectJammerTimes(
          state,
          team1: const Duration(seconds: 15),
          team2: Duration.zero,
        );
      },
    );

    test(
      'Scenario 9: a completed first penalty is not reduced again',
      () async {
        final state = await runningState();
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 15));
        seatJammer(state, 2, '20', penalties: 2);
        state.clearSeat(state.team1Jammer);
        state.tick(const Duration(seconds: 20));
        seatJammer(state, 1, '11');

        expectJammerTimes(
          state,
          team1: const Duration(seconds: 5),
          team2: Duration.zero,
        );
      },
    );

    test(
      'Scenario 10: no swap occurs when the other jammer has left',
      () async {
        final state = await runningState();
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 10));
        state.clearSeat(state.team1Jammer);
        seatJammer(state, 2, '20');

        expectTimeRemaining(state.team2Jammer, const Duration(seconds: 30));
      },
    );

    test(
      'Scenario 11: a manual return can retain remaining time and a new penalty',
      () async {
        final state = await runningState();
        seatJammer(state, 1, '10', penalties: 2);
        state.adjustTime(state.team1Jammer, const Duration(seconds: -10));

        expectTimeRemaining(state.team1Jammer, const Duration(seconds: 50));
      },
    );

    test(
      'Scenario 12: an officiating-error return adds no extra penalty',
      () async {
        final state = await runningState();
        seatJammer(state, 1, '10');
        state.adjustTime(state.team1Jammer, const Duration(seconds: -10));

        expectTimeRemaining(state.team1Jammer, const Duration(seconds: 20));
      },
    );

    test(
      'Scenario 13: an officiating-error return can be immediately released',
      () async {
        final state = await runningState();
        seatJammer(state, 1, '10');
        state.adjustTime(state.team1Jammer, const Duration(seconds: -30));

        expectTimeRemaining(state.team1Jammer, Duration.zero);
        expect(state.team1Jammer.isRunning, isFalse);
      },
    );

    test('Scenario 14: three penalties support sequential swaps', () async {
      final state = await runningState();
      seatJammer(state, 1, '10', penalties: 3);
      state.tick(const Duration(seconds: 10));
      seatJammer(state, 2, '20');
      state.clearSeat(state.team2Jammer);
      state.tick(const Duration(seconds: 5));
      seatJammer(state, 2, '21');

      expectTimeRemaining(state.team1Jammer, const Duration(seconds: 15));
      expect(state.team1Jammer.unmatchedPenalties, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Known number persistence
  // ---------------------------------------------------------------------------

  group('Known number persistence', () {
    test('numbers added are saved to SharedPreferences', () async {
      final state = makeState();
      await startEngine(state);

      state.addKnownNumber(1, '77');
      // Give the async save a moment
      await Future.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('jambox_known_t1'), contains('77'));
    });

    test('saved numbers are loaded back on next initialize', () async {
      SharedPreferences.setMockInitialValues({
        'jambox_known_t1': ['55'],
        'jambox_known_t2': <String>[],
      });

      final state = makeState();
      await startEngine(state);

      expect(state.knownNumbers(1), contains('55'));
    });
  });

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  group('App lifecycle', () {
    test('resumed event resets tick baseline without throwing', () async {
      final state = makeState();
      final engine = await startEngine(state);

      // Should not throw or cause negative time jumps.
      engine.didChangeAppLifecycleState(AppLifecycleState.resumed);
    });
  });
}
