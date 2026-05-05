import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/skater_seat.dart';

import '../test_helpers.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  SkaterSeat emptySeat({SkaterPosition position = SkaterPosition.blocker}) =>
      SkaterSeat(id: 'test', teamIndex: 1, position: position);

  SkaterSeat occupiedSeat({
    String number = '42',
    SkaterPosition position = SkaterPosition.jammer,
    Duration timeRemaining = const Duration(seconds: 25),
    bool isRunning = true,
    int penaltyCount = 1,
  }) {
    final seat = SkaterSeat(id: 'test', teamIndex: 1, position: position);
    seat.skaterNumber = number;
    seat.timeRemaining = timeRemaining;
    seat.isRunning = isRunning;
    seat.penaltyCount = penaltyCount;
    return seat;
  }

  // ---------------------------------------------------------------------------
  // state getter
  // ---------------------------------------------------------------------------

  group('state getter', () {
    test('empty seat is SeatState.empty', () {
      expectSeatState(emptySeat(), SeatState.empty);
    });

    test('occupied, not running → paused', () {
      final seat = occupiedSeat(isRunning: false);
      expectSeatState(seat, SeatState.paused);
    });

    test('running with >10s remaining → running', () {
      final seat = occupiedSeat(timeRemaining: const Duration(seconds: 11));
      expectSeatState(seat, SeatState.running);
    });

    test('running with exactly 10s remaining → standing', () {
      final seat = occupiedSeat(timeRemaining: const Duration(seconds: 10));
      expectSeatState(seat, SeatState.standing);
    });

    test('running with <10s remaining → standing', () {
      final seat = occupiedSeat(timeRemaining: const Duration(seconds: 5));
      expectSeatState(seat, SeatState.standing);
    });

    test('time at zero → done, regardless of isRunning', () {
      final runningAtZero = occupiedSeat(
        timeRemaining: Duration.zero,
        isRunning: true,
      );
      final pausedAtZero = occupiedSeat(
        timeRemaining: Duration.zero,
        isRunning: false,
      );
      expectSeatState(runningAtZero, SeatState.done);
      expectSeatState(pausedAtZero, SeatState.done);
    });
  });

  // ---------------------------------------------------------------------------
  // setSkater
  // ---------------------------------------------------------------------------

  group('setSkater()', () {
    test('sets number, position, 30s, penaltyCount=1, isRunning=false', () {
      final seat = emptySeat();
      seat.setSkater(number: '99', pos: SkaterPosition.jammer);

      expect(seat.skaterNumber, '99');
      expect(seat.position, SkaterPosition.jammer);
      expect(seat.timeRemaining, const Duration(seconds: 30));
      expect(seat.penaltyCount, 1);
      expect(seat.isRunning, isFalse);
    });

    test('arrivedBetweenJams reflects arrivedBetween argument', () {
      final seat = emptySeat();
      seat.setSkater(
        number: '1',
        pos: SkaterPosition.blocker,
        arrivedBetween: true,
      );
      expect(seat.arrivedBetweenJams, isTrue);

      seat.setSkater(
        number: '2',
        pos: SkaterPosition.blocker,
        arrivedBetween: false,
      );
      expect(seat.arrivedBetweenJams, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // addPenalty / removePenalty
  // ---------------------------------------------------------------------------

  group('addPenalty() / removePenalty()', () {
    test('addPenalty adds 30s and increments penaltyCount', () {
      final seat = emptySeat();
      seat.setSkater(number: '1', pos: SkaterPosition.blocker);
      seat.addPenalty();

      expect(seat.timeRemaining, const Duration(seconds: 60));
      expect(seat.penaltyCount, 2);
    });

    test('multiple addPenalty calls accumulate', () {
      final seat = emptySeat();
      seat.setSkater(number: '1', pos: SkaterPosition.blocker);
      seat.addPenalty();
      seat.addPenalty();

      expect(seat.timeRemaining, const Duration(seconds: 90));
      expect(seat.penaltyCount, 3);
    });

    test('removePenalty decrements penaltyCount', () {
      final seat = occupiedSeat(penaltyCount: 2);
      seat.removePenalty();
      expect(seat.penaltyCount, 1);
    });

    test('removePenalty floors at 1 — never goes below', () {
      final seat = occupiedSeat(penaltyCount: 1);
      seat.removePenalty();
      seat.removePenalty();
      expect(seat.penaltyCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // clear
  // ---------------------------------------------------------------------------

  group('clear()', () {
    test('resets all fields to defaults', () {
      final seat = occupiedSeat(penaltyCount: 3);
      seat.isInQueue = true;
      seat.arrivedBetweenJams = true;
      seat.clear();

      expect(seat.skaterNumber, '');
      expect(seat.timeRemaining, Duration.zero);
      expect(seat.isRunning, isFalse);
      expect(seat.isInQueue, isFalse);
      expect(seat.arrivedBetweenJams, isFalse);
      expect(seat.penaltyCount, 0);
      expect(seat.isEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  group('copyWith()', () {
    test('unspecified fields are preserved', () {
      final seat = occupiedSeat(
        number: '77',
        penaltyCount: 2,
        timeRemaining: const Duration(seconds: 20),
      );
      final copy = seat.copyWith();

      expect(copy.skaterNumber, '77');
      expect(copy.penaltyCount, 2);
      expect(copy.timeRemaining, const Duration(seconds: 20));
    });

    test('specified fields override originals', () {
      final seat = occupiedSeat(number: '10', penaltyCount: 1);
      final copy = seat.copyWith(
        skaterNumber: '99',
        penaltyCount: 3,
        timeRemaining: const Duration(seconds: 15),
      );

      expect(copy.skaterNumber, '99');
      expect(copy.penaltyCount, 3);
      expect(copy.timeRemaining, const Duration(seconds: 15));
      // Original unchanged
      expect(seat.skaterNumber, '10');
      expect(seat.penaltyCount, 1);
    });

    test('id is always preserved', () {
      final seat = emptySeat();
      expect(seat.copyWith().id, seat.id);
    });
  });

  // ---------------------------------------------------------------------------
  // isEmpty / isOccupied
  // ---------------------------------------------------------------------------

  group('isEmpty / isOccupied', () {
    test('empty seat: isEmpty=true, isOccupied=false', () {
      final seat = emptySeat();
      expect(seat.isEmpty, isTrue);
      expect(seat.isOccupied, isFalse);
    });

    test('occupied seat: isEmpty=false, isOccupied=true', () {
      final seat = occupiedSeat();
      expect(seat.isEmpty, isFalse);
      expect(seat.isOccupied, isTrue);
    });
  });
}
