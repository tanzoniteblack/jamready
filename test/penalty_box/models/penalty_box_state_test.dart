import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';

import '../test_helpers.dart';

void main() {
  late PenaltyBoxState state;

  setUp(() {
    state = makeState();
  });

  // ---------------------------------------------------------------------------
  // tick()
  // ---------------------------------------------------------------------------

  group('tick()', () {
    test('running seat decrements by elapsed duration', () {
      seatJammer(state, 1, '10');
      state.jamRunning = true;
      state.team1Jammer.isRunning = true;

      state.tick(const Duration(seconds: 5));

      expectTimeRemaining(state.team1Jammer, const Duration(seconds: 25));
    });

    test('paused seat is unaffected by tick', () {
      seatJammer(state, 1, '10');
      state.team1Jammer.isRunning = false;

      state.tick(const Duration(seconds: 10));

      expectTimeRemaining(state.team1Jammer, const Duration(seconds: 30));
    });

    test('seat stops when timeRemaining reaches zero', () {
      seatJammer(state, 1, '10');
      state.team1Jammer.isRunning = true;

      state.tick(const Duration(seconds: 30));

      expect(state.team1Jammer.isRunning, isFalse);
      expectTimeRemaining(state.team1Jammer, Duration.zero);
    });

    test('timeRemaining clamps to zero, never negative', () {
      seatJammer(state, 1, '10');
      state.team1Jammer.isRunning = true;

      state.tick(const Duration(seconds: 60));

      expectTimeRemaining(state.team1Jammer, Duration.zero);
    });

    test('multiple seats tick independently', () {
      seatJammer(state, 1, '10');
      seatBlocker(state, 1, '22');
      state.team1Jammer.isRunning = true;
      state.team1Blocker1.isRunning = false;

      state.tick(const Duration(seconds: 10));

      expectTimeRemaining(state.team1Jammer, const Duration(seconds: 20));
      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 30));
    });
  });

  // ---------------------------------------------------------------------------
  // onJamStart() / onJamEnd()
  // ---------------------------------------------------------------------------

  group('onJamStart() / onJamEnd()', () {
    test('onJamStart sets jamRunning=true and starts all occupied seats', () {
      seatJammer(state, 1, '10');
      seatBlocker(state, 1, '22');
      state.team1Jammer.isRunning = false;
      state.team1Blocker1.isRunning = false;

      state.onJamStart();

      expect(state.jamRunning, isTrue);
      expect(state.team1Jammer.isRunning, isTrue);
      expect(state.team1Blocker1.isRunning, isTrue);
    });

    test('onJamStart clears arrivedBetweenJams on all seats', () {
      seatJammer(state, 1, '10');
      state.team1Jammer.arrivedBetweenJams = true;

      state.onJamStart();

      expect(state.team1Jammer.arrivedBetweenJams, isFalse);
    });

    test('onJamStart releases jammer with 0s remaining (§4.2.5)', () {
      seatJammer(state, 1, '10');
      state.team1Jammer.timeRemaining = Duration.zero;

      state.onJamStart();

      expectSeatEmpty(state.team1Jammer);
    });

    test('onJamStart does not release jammer with time remaining', () {
      seatJammer(state, 1, '10');

      state.onJamStart();

      expectSeatOccupied(state.team1Jammer, '10');
    });

    test('onJamEnd sets jamRunning=false and pauses all running seats', () {
      seatJammer(state, 1, '10');
      seatBlocker(state, 1, '22');
      state.onJamStart();

      state.onJamEnd();

      expect(state.jamRunning, isFalse);
      expect(state.team1Jammer.isRunning, isFalse);
      expect(state.team1Blocker1.isRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // seatSkater()
  // ---------------------------------------------------------------------------

  group('seatSkater()', () {
    test('seats skater with 30s and isRunning=true when jam is running', () {
      state.jamRunning = true;
      state.seatSkater(
        seat: state.team1Blocker1,
        number: '55',
        position: SkaterPosition.blocker,
      );

      expectSeatOccupied(state.team1Blocker1, '55');
      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 30));
      expect(state.team1Blocker1.isRunning, isTrue);
    });

    test('seated skater is paused when jam is not running', () {
      state.jamRunning = false;
      state.seatSkater(
        seat: state.team1Blocker1,
        number: '55',
        position: SkaterPosition.blocker,
      );

      expect(state.team1Blocker1.isRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // startSeatAnonymously()
  // ---------------------------------------------------------------------------

  group('startSeatAnonymously()', () {
    test(
      'sets placeholder number, 30s, penaltyCount=1, unmatchedPenalties=1',
      () {
        state.startSeatAnonymously(state.team1Blocker1);

        expect(state.team1Blocker1.skaterNumber, '?');
        expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 30));
        expect(state.team1Blocker1.penaltyCount, 1);
        expect(state.team1Blocker1.unmatchedPenalties, 1);
      },
    );

    test('isRunning=true when jam is running', () {
      state.jamRunning = true;
      state.startSeatAnonymously(state.team1Blocker1);
      expect(state.team1Blocker1.isRunning, isTrue);
    });

    test('isRunning=false when jam is not running', () {
      state.jamRunning = false;
      state.startSeatAnonymously(state.team1Blocker1);
      expect(state.team1Blocker1.isRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // clearSeat() — local mode
  // ---------------------------------------------------------------------------

  group('clearSeat() — local mode (no callbacks)', () {
    test('clears an occupied seat', () {
      seatJammer(state, 1, '10');
      state.clearSeat(state.team1Jammer);
      expectSeatEmpty(state.team1Jammer);
    });

    test('promotes first queue entry into a blocker seat when available', () {
      seatBlocker(state, 1, '11', seatIndex: 0);
      seatBlocker(state, 1, '22', seatIndex: 1);
      state.addToQueue(
        teamIdx: 1,
        number: '33',
        position: SkaterPosition.blocker,
      );

      state.clearSeat(state.team1Blocker1);

      expect(state.team1Blocker1.skaterNumber, '33');
      expect(state.queueForTeam(1), isEmpty);
    });

    test('does not promote queue into jammer seat', () {
      seatJammer(state, 1, '10');
      state.addToQueue(
        teamIdx: 1,
        number: '33',
        position: SkaterPosition.blocker,
      );

      state.clearSeat(state.team1Jammer);

      expectSeatEmpty(state.team1Jammer);
      expect(state.queueForTeam(1), hasLength(1));
    });

    test('does not promote when queue is empty', () {
      seatBlocker(state, 1, '11');
      state.clearSeat(state.team1Blocker1);
      expectSeatEmpty(state.team1Blocker1);
    });
  });

  // ---------------------------------------------------------------------------
  // addPenaltyToSeat / removePenaltyFromSeat
  // ---------------------------------------------------------------------------

  group('addPenaltyToSeat() / removePenaltyFromSeat()', () {
    test('addPenalty adds 30s', () {
      seatBlocker(state, 1, '11');

      state.addPenaltyToSeat(state.team1Blocker1);

      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 60));
    });

    test('removePenalty removes 30s', () {
      seatBlocker(state, 1, '11');
      state.addPenaltyToSeat(
        state.team1Blocker1,
      ); // A second penalty adds 30 seconds.
      state.removePenaltyFromSeat(state.team1Blocker1);

      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 30));
    });

    test('removePenalty clamps timeRemaining to zero', () {
      seatBlocker(state, 1, '11');
      state.team1Blocker1.timeRemaining = const Duration(seconds: 10);

      state.removePenaltyFromSeat(state.team1Blocker1);

      expectTimeRemaining(state.team1Blocker1, Duration.zero);
      expect(state.team1Blocker1.isRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // adjustTime()
  // ---------------------------------------------------------------------------

  group('adjustTime()', () {
    test('adds time within bounds', () {
      seatBlocker(state, 1, '11');
      state.adjustTime(state.team1Blocker1, const Duration(seconds: 10));
      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 40));
    });

    test('clamps to 5:00 maximum', () {
      seatBlocker(state, 1, '11');
      state.adjustTime(state.team1Blocker1, const Duration(minutes: 10));
      expectTimeRemaining(state.team1Blocker1, const Duration(minutes: 5));
    });

    test('clamps to 0:00 minimum', () {
      seatBlocker(state, 1, '11');
      state.adjustTime(state.team1Blocker1, const Duration(seconds: -60));
      expectTimeRemaining(state.team1Blocker1, Duration.zero);
    });
  });

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  group('Queue management', () {
    test('addToQueue returns new seat, visible in queueForTeam', () {
      final q = state.addToQueue(
        teamIdx: 1,
        number: '88',
        position: SkaterPosition.blocker,
      );

      expect(q.skaterNumber, '88');
      expect(state.queueForTeam(1), contains(q));
    });

    test('queueForTeam filters by team', () {
      state.addToQueue(
        teamIdx: 1,
        number: '11',
        position: SkaterPosition.blocker,
      );
      state.addToQueue(
        teamIdx: 2,
        number: '22',
        position: SkaterPosition.blocker,
      );

      expect(state.queueForTeam(1), hasLength(1));
      expect(state.queueForTeam(2), hasLength(1));
    });

    test('removeFromQueue removes the entry', () {
      final q = state.addToQueue(
        teamIdx: 1,
        number: '11',
        position: SkaterPosition.blocker,
      );
      state.removeFromQueue(q);

      expect(state.queueForTeam(1), isEmpty);
    });

    test('multiple blockers queue in FIFO order', () {
      state.addToQueue(
        teamIdx: 1,
        number: 'A',
        position: SkaterPosition.blocker,
      );
      state.addToQueue(
        teamIdx: 1,
        number: 'B',
        position: SkaterPosition.blocker,
      );
      state.addToQueue(
        teamIdx: 1,
        number: 'C',
        position: SkaterPosition.blocker,
      );

      final q = state.queueForTeam(1);
      expect(q.map((s) => s.skaterNumber), ['A', 'B', 'C']);
    });
  });

  // ---------------------------------------------------------------------------
  // Roster / UUID mapping
  // ---------------------------------------------------------------------------

  group('Roster / UUID mapping', () {
    test('updateRoster maps number → uuid', () {
      state.updateRoster(1, '42', 'uuid-abc');
      expect(state.lookupSkaterId(1, '42'), 'uuid-abc');
    });

    test('lookupSkaterId returns null for unknown number', () {
      expect(state.lookupSkaterId(1, '999'), isNull);
    });

    test('skaterNumberByUuid reverse lookup', () {
      state.updateRoster(1, '42', 'uuid-abc');
      expect(state.skaterNumberByUuid(1, 'uuid-abc'), '42');
    });

    test('roster is team-scoped', () {
      state.updateRoster(1, '42', 'uuid-t1');
      state.updateRoster(2, '42', 'uuid-t2');

      expect(state.lookupSkaterId(1, '42'), 'uuid-t1');
      expect(state.lookupSkaterId(2, '42'), 'uuid-t2');
    });
  });

  // ---------------------------------------------------------------------------
  // §4.4 Jammer arrival sync
  // ---------------------------------------------------------------------------

  group('_applyJammerArrivalSync() — WFTDA §4.4', () {
    // Start each test during a jam so newly seated jammers begin serving time.

    setUp(() => state.onJamStart());

    test('only one jammer seated — no sync, gets full 30s', () {
      seatJammer(state, 2, '20');

      expectTimeRemaining(state.team2Jammer, const Duration(seconds: 30));
    });

    test(
      'sitting jammer not running — no sync, arriving gets full 30s (§4.4 guard)',
      () {
        // Put T1 in the box without starting their timer.
        state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
        state.team1Jammer.isRunning =
            false; // A paused jammer cannot swap time.

        seatJammer(state, 2, '20');

        expectTimeRemaining(state.team2Jammer, const Duration(seconds: 30));
      },
    );

    test(
      'simple swap: 1-penalty each, 10s elapsed — sitting released, arriving gets 10s (§4.4.1)',
      () {
        seatJammer(state, 1, '10');
        // T1 serves 10 seconds before T2 arrives.
        state.tick(const Duration(seconds: 10));

        seatJammer(state, 2, '20');

        expectJammerTimes(
          state,
          team1: Duration.zero,
          team2: const Duration(seconds: 10),
        );
        expect(state.team1Jammer.isRunning, isFalse);
      },
    );

    test(
      'arriving just as sitting seated (0 elapsed) — sitting released, arriving gets ~0s',
      () {
        seatJammer(state, 1, '10'); // T1 has not yet served any time.

        seatJammer(state, 2, '20');

        expectJammerTimes(state, team1: Duration.zero, team2: Duration.zero);
      },
    );

    test(
      'sitting has 2 penalties with enough time: arriving 1-penalty cancels against one, sitting released of excess, arriving released (§4.4.2)',
      () {
        // T1 receives two penalties, for 60 seconds total. After 20 seconds,
        // T1 has 40 seconds left.
        seatJammer(state, 1, '10');
        state.addPenaltyToSeat(state.team1Jammer);
        state.tick(const Duration(seconds: 20));

        // T2 now arrives with one penalty. It cancels one of T1's two
        // outstanding penalties. T2 is released immediately; T1 has already
        // served 20 seconds and keeps the final 10 seconds of the remaining
        // penalty.
        seatJammer(state, 2, '20');

        expect(state.team1Jammer.timeRemaining, const Duration(seconds: 10));
        expect(state.team2Jammer.timeRemaining, Duration.zero);
        expect(state.team2Jammer.isRunning, isFalse);
      },
    );

    test(
      'completed penalties are not matched with a later arrival (Scenario 3)',
      () {
        // T1 receives two penalties, for 60 seconds total. After 55 seconds,
        // their first penalty is complete and the second has 5 seconds left.
        seatJammer(state, 1, '10');
        state.addPenaltyToSeat(state.team1Jammer);
        state.tick(const Duration(seconds: 55));

        // T2 arrives with 1 penalty. Only T1's active, second penalty is
        // eligible for the swap, so both penalties are shortened by 25s.
        seatJammer(state, 2, '20');

        expect(state.team1Jammer.timeRemaining, Duration.zero);
        expect(state.team2Jammer.timeRemaining, const Duration(seconds: 25));
      },
    );

    test(
      'sitting has 2 penalties, exactly 30s remaining: arriving gets elapsed of second penalty, sitting released',
      () {
        // T1 receives two penalties. After 30 seconds, their first penalty is
        // complete and the second has 30 seconds left.
        seatJammer(state, 1, '10');
        state.addPenaltyToSeat(state.team1Jammer);
        state.tick(const Duration(seconds: 30));

        // T2 arrives with one penalty. T1's remaining penalty and T2's new
        // penalty cancel each other completely, so both are released.
        seatJammer(state, 2, '20');

        expect(state.team1Jammer.timeRemaining, Duration.zero);
        expect(state.team2Jammer.timeRemaining, Duration.zero);
      },
    );

    test('onJamStart releases jammer at 0s (§4.2.5)', () {
      // Seat T1 jammer with expired time then trigger jam start.
      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.timeRemaining = Duration.zero;
      state.onJamEnd(); // End the jam before starting the next one.
      state.onJamStart();

      expectSeatEmpty(state.team1Jammer);
      // T2 remains empty.
      expectSeatEmpty(state.team2Jammer);
    });

    test('jammer sync does not affect blocker seats', () {
      seatJammer(state, 1, '10');
      seatBlocker(state, 1, '22');
      state.tick(const Duration(seconds: 5));

      seatJammer(state, 2, '20');

      // Jammer swaps do not change blocker time.
      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 25));
    });

    // --- Scenario 6: returning jammer after a swap serves full time ---

    test(
      'returning jammer after swap serves full 30s, committed time unaffected (Scenario 6)',
      () {
        // T1 has one penalty and serves 10 seconds, leaving 20 seconds.
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 10));

        // T2 then arrives with one penalty. Their penalties swap: T1 is
        // released, T2 has 10 seconds left, and that penalty is fully paired.
        seatJammer(state, 2, '20');
        expect(state.team1Jammer.timeRemaining, Duration.zero);
        expect(state.team2Jammer.timeRemaining, const Duration(seconds: 10));

        // T1 leaves the box while T2 is still serving time.
        state.clearSeat(state.team1Jammer);

        // T1 returns with a new penalty. Because T2's remaining time has
        // already been paired, T1 serves the full 30 seconds.
        seatJammer(state, 1, '11');
        expectJammerTimes(
          state,
          team1: const Duration(seconds: 30),
          team2: const Duration(seconds: 10),
        );
      },
    );

    test(
      'returning jammer, sitting jammer almost done — full penalty still applies (Scenario 6b)',
      () {
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 10));

        seatJammer(state, 2, '20'); // T2 has 10 seconds left after the swap.
        state.clearSeat(state.team1Jammer);

        // T2 serves another 8 seconds, leaving 2 seconds.
        state.tick(const Duration(seconds: 8));

        // T1's new penalty is separate from T2's already paired time.
        seatJammer(state, 1, '11');
        expectJammerTimes(
          state,
          team1: const Duration(seconds: 30),
          team2: const Duration(seconds: 2),
        );
      },
    );

    // --- Scenario 7: arriving jammer has more penalties than sitting ---

    test(
      'arriving jammer with 2 penalties: matched pair resolved, extra penalty unaffected (Scenario 7)',
      () {
        // T1 has one penalty and has served 10 seconds, leaving 20 seconds.
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 10));

        // T2 arrives with two penalties. One pairs with T1's penalty; the
        // other remains to be served. T1 is released and T2 has 40 seconds.
        seatJammer(state, 2, '20', penalties: 2);

        expectJammerTimes(
          state,
          team1: Duration.zero,
          team2: const Duration(seconds: 40),
        );
        expect(state.team1Jammer.isRunning, isFalse);
        expect(state.team2Jammer.unmatchedPenalties, 1);
      },
    );

    // --- Scenario 8: second swap matches opponent's remaining unmatched penalty ---

    test(
      'second swap: returning jammer matches opponent\'s unmatched second penalty (Scenario 8)',
      () {
        // Blue has one penalty and has served 10 seconds, leaving 20 seconds.
        seatJammer(state, 1, '10');
        state.tick(const Duration(seconds: 10));

        // Pink arrives with two penalties. The first pairs with Blue's
        // penalty, leaving Pink with 40 seconds from the second penalty.
        seatJammer(state, 2, '20', penalties: 2);
        state.clearSeat(state.team1Jammer);

        // Pink serves 15 seconds, leaving 25 seconds on the unpaired penalty.
        state.tick(const Duration(seconds: 15));
        expect(state.team2Jammer.timeRemaining, const Duration(seconds: 25));

        // Blue returns with one new penalty. It pairs with Pink's remaining
        // penalty: Pink is released and Blue has 5 seconds left.
        seatJammer(state, 1, '11');
        expectJammerTimes(
          state,
          team1: const Duration(seconds: 5),
          team2: Duration.zero,
        );
        expect(state.team2Jammer.isRunning, isFalse);
      },
    );

    // --- Scenario 14: 3-penalty jammer vs sequential 1-penalty arrivals ---

    test('3-penalty jammer vs sequential 1-penalty arrivals (Scenario 14)', () {
      // T1 receives three penalties, for 90 seconds total. After 10 seconds,
      // T1 has 80 seconds left.
      seatJammer(state, 1, '10', penalties: 3);
      state.tick(const Duration(seconds: 10));

      // T2 arrives with one penalty. It pairs with one of T1's penalties, so
      // T2 is released and T1 has 50 seconds left across two unpaired penalties.
      seatJammer(state, 2, '20');
      expect(state.team2Jammer.timeRemaining, Duration.zero);
      expect(state.team2Jammer.isRunning, isFalse);
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 50));
      expect(state.team1Jammer.unmatchedPenalties, 2);

      state.clearSeat(state.team2Jammer);
      state.tick(const Duration(seconds: 5));

      // T2 returns with another penalty. It pairs with T1's next unpaired
      // penalty, so T2 is released again and T1 has 15 seconds left.
      seatJammer(state, 2, '21');
      expect(state.team2Jammer.timeRemaining, Duration.zero);
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 15));
      expect(state.team1Jammer.unmatchedPenalties, 1);
    });
  });
}
