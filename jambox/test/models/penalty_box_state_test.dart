import 'package:flutter_test/flutter_test.dart';
import 'package:pbm_ready/models/penalty_box_state.dart';
import 'package:pbm_ready/models/skater_seat.dart';

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

    test('fires onSeatStarted and onSkaterAssigned callbacks', () {
      String? startedId;
      String? assignedNumber;
      state.onSeatStarted = (s) => startedId = s.id;
      state.onSkaterAssigned = (s, n) => assignedNumber = n;

      state.seatSkater(
        seat: state.team1Jammer,
        number: '42',
        position: SkaterPosition.jammer,
      );

      expect(startedId, state.team1Jammer.id);
      expect(assignedNumber, '42');
    });
  });

  // ---------------------------------------------------------------------------
  // startSeatAnonymously()
  // ---------------------------------------------------------------------------

  group('startSeatAnonymously()', () {
    test('sets placeholder number, 30s, penaltyCount=1, unmatchedPenalties=1', () {
      state.startSeatAnonymously(state.team1Blocker1);

      expect(state.team1Blocker1.skaterNumber, '?');
      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 30));
      expect(state.team1Blocker1.penaltyCount, 1);
      expect(state.team1Blocker1.unmatchedPenalties, 1);
    });

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
      state.addToQueue(teamIdx: 1, number: '33', position: SkaterPosition.blocker);

      state.clearSeat(state.team1Blocker1);

      expect(state.team1Blocker1.skaterNumber, '33');
      expect(state.queueForTeam(1), isEmpty);
    });

    test('does not promote queue into jammer seat', () {
      seatJammer(state, 1, '10');
      state.addToQueue(teamIdx: 1, number: '33', position: SkaterPosition.blocker);

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

  group('clearSeat() — BoxSeat mode (onSeatCleared callback set)', () {
    setUp(() {
      state.onSeatCleared = (_) {};
    });

    test('calls onSeatCleared and does NOT promote from queue', () {
      seatBlocker(state, 1, '11', seatIndex: 0);
      state.addToQueue(teamIdx: 1, number: '33', position: SkaterPosition.blocker);

      String? clearedId;
      state.onSeatCleared = (s) => clearedId = s.id;
      state.clearSeat(state.team1Blocker1);

      expect(clearedId, state.team1Blocker1.id);
      // Seat is cleared
      expectSeatEmpty(state.team1Blocker1);
      // Queue is preserved — server decides promotion
      expect(state.queueForTeam(1), hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // addPenaltyToSeat / removePenaltyFromSeat
  // ---------------------------------------------------------------------------

  group('addPenaltyToSeat() / removePenaltyFromSeat()', () {
    test('addPenalty adds 30s and fires onSeatTimeChanged with +30', () {
      seatBlocker(state, 1, '11');
      int? sentDelta;
      state.onSeatTimeChanged = (_, d) => sentDelta = d;

      state.addPenaltyToSeat(state.team1Blocker1);

      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 60));
      expect(sentDelta, 30);
    });

    test('removePenalty removes 30s and fires onSeatTimeChanged with -30', () {
      seatBlocker(state, 1, '11');
      state.addPenaltyToSeat(state.team1Blocker1); // 60s, penaltyCount=2
      int? sentDelta;
      state.onSeatTimeChanged = (_, d) => sentDelta = d;

      state.removePenaltyFromSeat(state.team1Blocker1);

      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 30));
      expect(sentDelta, -30);
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

    test('fires onSeatTimeChanged with delta in seconds', () {
      seatBlocker(state, 1, '11');
      int? sentDelta;
      state.onSeatTimeChanged = (_, d) => sentDelta = d;

      state.adjustTime(state.team1Blocker1, const Duration(seconds: 15));

      expect(sentDelta, 15);
    });
  });

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  group('Queue management', () {
    test('addToQueue returns new seat, visible in queueForTeam', () {
      final q = state.addToQueue(
          teamIdx: 1, number: '88', position: SkaterPosition.blocker);

      expect(q.skaterNumber, '88');
      expect(state.queueForTeam(1), contains(q));
    });

    test('queueForTeam filters by team', () {
      state.addToQueue(teamIdx: 1, number: '11', position: SkaterPosition.blocker);
      state.addToQueue(teamIdx: 2, number: '22', position: SkaterPosition.blocker);

      expect(state.queueForTeam(1), hasLength(1));
      expect(state.queueForTeam(2), hasLength(1));
    });

    test('removeFromQueue removes the entry', () {
      final q = state.addToQueue(
          teamIdx: 1, number: '11', position: SkaterPosition.blocker);
      state.removeFromQueue(q);

      expect(state.queueForTeam(1), isEmpty);
    });

    test('multiple blockers queue in FIFO order', () {
      state.addToQueue(teamIdx: 1, number: 'A', position: SkaterPosition.blocker);
      state.addToQueue(teamIdx: 1, number: 'B', position: SkaterPosition.blocker);
      state.addToQueue(teamIdx: 1, number: 'C', position: SkaterPosition.blocker);

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
    // All tests start the jam first so isRunning=true on seated jammers.

    setUp(() => state.onJamStart());

    test('only one jammer seated — no sync, gets full 30s', () {
      seatJammer(state, 2, '20');

      expectTimeRemaining(state.team2Jammer, const Duration(seconds: 30));
    });

    test('sitting jammer not running — no sync, arriving gets full 30s (§4.4 guard)', () {
      // Seat T1 jammer manually without triggering sync
      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.isRunning = false; // paused — should not trigger sync

      seatJammer(state, 2, '20');

      expectTimeRemaining(state.team2Jammer, const Duration(seconds: 30));
    });

    test('simple swap: 1-penalty each, 10s elapsed — sitting released, arriving gets 10s (§4.4.1)', () {
      seatJammer(state, 1, '10');
      // Simulate 10 seconds served by T1
      state.tick(const Duration(seconds: 10));

      seatJammer(state, 2, '20');

      expectJammerTimes(
        state,
        team1: Duration.zero,                   // sitting released
        team2: const Duration(seconds: 10),     // arriving serves elapsed
      );
      expect(state.team1Jammer.isRunning, isFalse);
    });

    test('arriving just as sitting seated (0 elapsed) — sitting released, arriving gets ~0s', () {
      seatJammer(state, 1, '10'); // 30s remaining, 0 elapsed

      seatJammer(state, 2, '20');

      expectJammerTimes(state, team1: Duration.zero, team2: Duration.zero);
    });

    test('sitting has 2 penalties with enough time: arriving 1-penalty cancels against one, sitting released of excess, arriving released (§4.4.2)', () {
      // T1: seated, then given a second penalty → penaltyCount=2, timeRemaining=60s.
      // Tick 20s → T1 has 40s remaining.
      seatJammer(state, 1, '10');
      state.addPenaltyToSeat(state.team1Jammer); // → 60s, penaltyCount=2
      state.tick(const Duration(seconds: 20));   // → 40s remaining

      // T2 arrives with 1 penalty (penaltyCount=1 at sync time — always from setSkater).
      // sittingMax=60, arrivingMax=30, sittingTime=40, arrivingTime=30.
      // Loop: 40≥30 AND 30≥30 → sittingTime=10, arrivingTime=0, sittingMax=30, arrivingMax=0.
      // arrivingMax==0 → T2 fully cancelled (released), T1 keeps 10s.
      seatJammer(state, 2, '20');

      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 10));
      expect(state.team2Jammer.timeRemaining, Duration.zero);
      expect(state.team2Jammer.isRunning, isFalse);
    });

    test('sitting has 2 penalties with little time: nightmare scenario — arriving gets full 30s (§4.4.3)', () {
      // T1: 2 penalties, 60s. Tick 55s → T1 has 5s remaining.
      seatJammer(state, 1, '10');
      state.addPenaltyToSeat(state.team1Jammer); // → 60s, penaltyCount=2
      state.tick(const Duration(seconds: 55));   // → 5s remaining

      // T2 arrives with 1 penalty.
      // sittingMax=60, arrivingMax=30, sittingTime=5.
      // Loop: 5≥30? No → loop doesn't run.
      // sittingMax(60) != arrivingMax(30) → nightmare scenario.
      // T1 keeps 5s, T2 gets full 30s.
      seatJammer(state, 2, '20');

      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 5));
      expect(state.team2Jammer.timeRemaining, const Duration(seconds: 30));
    });

    test('sitting has 2 penalties, exactly 30s remaining: arriving gets elapsed of second penalty, sitting released', () {
      // T1: 2 penalties, 60s. Tick 30s → T1 has 30s remaining (sittingTime = 30s = 1 penalty).
      seatJammer(state, 1, '10');
      state.addPenaltyToSeat(state.team1Jammer); // → 60s, penaltyCount=2
      state.tick(const Duration(seconds: 30));   // → 30s remaining

      // T2 arrives.
      // sittingMax=60, arrivingMax=30, sittingTime=30, arrivingTime=30.
      // Loop: 30≥30 AND 30≥30 → sittingTime=0, arrivingTime=0, sittingMax=30, arrivingMax=0.
      // arrivingMax==0 → T2 released (0s), T1 released (0s).
      seatJammer(state, 2, '20');

      expect(state.team1Jammer.timeRemaining, Duration.zero);
      expect(state.team2Jammer.timeRemaining, Duration.zero);
    });

    test('onJamStart releases jammer at 0s (§4.2.5)', () {
      // Seat T1 jammer with expired time then trigger jam start.
      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.timeRemaining = Duration.zero;
      state.onJamEnd(); // reset jamRunning
      state.onJamStart();

      expectSeatEmpty(state.team1Jammer);
      // T2 unaffected
      expectSeatEmpty(state.team2Jammer);
    });

    test('jammer sync does not affect blocker seats', () {
      seatJammer(state, 1, '10');
      seatBlocker(state, 1, '22');
      state.tick(const Duration(seconds: 5));

      seatJammer(state, 2, '20');

      // Blocker seat time unchanged by jammer sync
      expectTimeRemaining(state.team1Blocker1, const Duration(seconds: 25));
    });

    // --- Scenario 6: returning jammer after a swap serves full time ---

    test('returning jammer after swap serves full 30s, committed time unaffected (Scenario 6)', () {
      // T1 (1 penalty) sits, 10s elapsed → 20s remaining
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 10));

      // T2 arrives (1 penalty) → simple swap: T1 released, T2 gets elapsed (10s)
      // T2.unmatchedPenalties = 0 after being matched
      seatJammer(state, 2, '20');
      expect(state.team1Jammer.timeRemaining, Duration.zero);
      expect(state.team2Jammer.timeRemaining, const Duration(seconds: 10));

      // Clear T1 (done); T2 is still serving
      state.clearSeat(state.team1Jammer);

      // T1 returns with a new penalty while T2 still serving
      // T2.unmatchedPenalties == 0 → early return → T1 gets full 30s
      seatJammer(state, 1, '11');
      expectJammerTimes(
        state,
        team1: const Duration(seconds: 30),
        team2: const Duration(seconds: 10),
      );
    });

    test('returning jammer, sitting jammer almost done — full penalty still applies (Scenario 6b)', () {
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 10));

      seatJammer(state, 2, '20'); // T2 gets 10s, unmatch=0
      state.clearSeat(state.team1Jammer);

      // T2 almost done
      state.tick(const Duration(seconds: 8)); // T2: 10s - 8s = 2s remaining

      // T1 returns — T2.unmatch==0 → full 30s, T2 time unchanged
      seatJammer(state, 1, '11');
      expectJammerTimes(
        state,
        team1: const Duration(seconds: 30),
        team2: const Duration(seconds: 2),
      );
    });

    // --- Scenario 7: arriving jammer has more penalties than sitting ---

    test('arriving jammer with 2 penalties: matched pair resolved, extra penalty unaffected (Scenario 7)', () {
      // T1 (1 penalty) sitting, 10s elapsed → 20s remaining
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 10)); // T1: 20s

      // T2 arrives with 2 penalties (60s, unmatch=2)
      // sittingMax=30, arrivingMax=60, sittingTime=20
      // §4.4.1 extended: elapsed=10, arrivingTime=10+(60-30)=40s; T1 released
      seatJammer(state, 2, '20', penalties: 2);

      expectJammerTimes(
        state,
        team1: Duration.zero,                  // released
        team2: const Duration(seconds: 40),    // elapsed(10) + unmatched penalty(30)
      );
      expect(state.team1Jammer.isRunning, isFalse);
      expect(state.team2Jammer.unmatchedPenalties, 1);
    });

    // --- Scenario 8: second swap matches opponent's remaining unmatched penalty ---

    test('second swap: returning jammer matches opponent\'s unmatched second penalty (Scenario 8)', () {
      // Blue (T1) seated, 10s elapsed → 20s remaining
      seatJammer(state, 1, '10');
      state.tick(const Duration(seconds: 10));

      // Pink (T2) arrives with 2 penalties → first swap
      // Blue→0s (released, unmatch=0), Pink→40s (unmatch=1)
      seatJammer(state, 2, '20', penalties: 2);
      state.clearSeat(state.team1Jammer);

      // Tick 15s: Pink serves 10s credit + 5s of unmatched penalty → 25s remaining
      state.tick(const Duration(seconds: 15));
      expect(state.team2Jammer.timeRemaining, const Duration(seconds: 25));

      // Blue returns with 1 new penalty → second swap
      // Pink's unmatched penalty has 5s elapsed (25s remaining of 30s unmatched)
      // Pink released (0s), Blue gets elapsed (5s)
      seatJammer(state, 1, '11');
      expectJammerTimes(
        state,
        team1: const Duration(seconds: 5),
        team2: Duration.zero,
      );
      expect(state.team2Jammer.isRunning, isFalse);
    });

    // --- Scenario 14: 3-penalty jammer vs sequential 1-penalty arrivals ---

    test('3-penalty jammer vs sequential 1-penalty arrivals (Scenario 14)', () {
      // T1 seated with 3 penalties (90s), 10s elapsed → 80s remaining
      seatJammer(state, 1, '10', penalties: 3);
      state.tick(const Duration(seconds: 10));

      // T2 first arrival (1 penalty): cancel one pair, T2 released, T1 reduced
      // sittingMax=90, arrivingMax=30, sittingTime=80
      // Loop: 80>=30 AND 30>=30 → sittingTime=50, arrivingTime=0, sittingMax=60, arrivingMax=0
      // arrivingMax==0 → T2 released, T1→50s, T1.unmatch=2
      seatJammer(state, 2, '20');
      expect(state.team2Jammer.timeRemaining, Duration.zero);
      expect(state.team2Jammer.isRunning, isFalse);
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 50));
      expect(state.team1Jammer.unmatchedPenalties, 2);

      state.clearSeat(state.team2Jammer);
      state.tick(const Duration(seconds: 5)); // T1: 45s remaining

      // T2 second arrival (1 penalty): cancel another pair, T2 released again
      // sittingMax=60, arrivingMax=30, sittingTime=45
      // Loop: 45>=30 AND 30>=30 → sittingTime=15, arrivingTime=0, sittingMax=30, arrivingMax=0
      // arrivingMax==0 → T2 released, T1→15s, T1.unmatch=1
      seatJammer(state, 2, '21');
      expect(state.team2Jammer.timeRemaining, Duration.zero);
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 15));
      expect(state.team1Jammer.unmatchedPenalties, 1);
    });
  });
}
