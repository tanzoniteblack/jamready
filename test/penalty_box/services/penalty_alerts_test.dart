import 'package:flutter_test/flutter_test.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/services/penalty_alerts.dart';

import '../test_helpers.dart';

void main() {
  late PenaltyBoxState state;

  setUp(() {
    state = makeState();
    state.jamRunning = true;
  });

  test('a running seat gets stand and release alerts', () {
    seatBlocker(state, 1, '22');
    state.team1Blocker1
      ..isRunning = true
      ..timeRemaining = const Duration(seconds: 25);

    final alerts = penaltyAlertsFor(state);

    expect(alerts.map((a) => a.delay), [
      const Duration(seconds: 13),
      const Duration(seconds: 23),
    ]);
    expect(alerts.first.title, 'Stand ${state.team1.name} #22');
    expect(alerts.last.title, 'Release ${state.team1.name} #22');
    expect(alerts.first.body, '10 seconds left.');
  });

  test('a seat already standing only gets a release alert', () {
    seatJammer(state, 2, '7');
    state.team2Jammer
      ..isRunning = true
      ..timeRemaining = const Duration(seconds: 8);

    final alerts = penaltyAlertsFor(state);

    expect(alerts, hasLength(1));
    expect(alerts.single.title, 'Release ${state.team2.name} #7');
    expect(alerts.single.delay, const Duration(seconds: 6));
  });

  test('a release under 2 seconds away alerts immediately', () {
    seatJammer(state, 1, '10');
    state.team1Jammer
      ..isRunning = true
      ..timeRemaining = const Duration(milliseconds: 1500);

    expect(penaltyAlertsFor(state).single.delay, Duration.zero);
  });

  test('paused, done, and empty seats get no alerts', () {
    seatBlocker(state, 1, '22');
    state.team1Blocker1.isRunning = false;
    seatJammer(state, 1, '10');
    state.team1Jammer
      ..isRunning = false
      ..timeRemaining = Duration.zero;

    expect(penaltyAlertsFor(state), isEmpty);
  });

  test('alerts for different seats never share an id', () {
    for (final seat in state.seats) {
      seat
        ..skaterNumber = '1'
        ..isRunning = true
        ..timeRemaining = const Duration(seconds: 30);
    }

    final ids = penaltyAlertsFor(state).map((a) => a.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
  });

  test('alerts say they depend on the jam when CRG controls it', () {
    seatBlocker(state, 1, '22');
    state.team1Blocker1.isRunning = true;

    final alerts = penaltyAlertsFor(state, jamMayStop: true);

    expect(alerts.first.body, '10 seconds left if the jam is still running.');
    expect(
      alerts.last.body,
      'Penalty time is almost done if the jam is still running.',
    );
  });

  group('NotificationAlertScheduler under a test binding', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    test(
      'treats notifications as declined without touching the plugin',
      () async {
        // No notification plugin is registered in tests, so any platform call
        // would throw here.
        final scheduler = NotificationAlertScheduler.instance;
        await scheduler.init();
        await scheduler.schedule(const [
          PenaltyAlert(
            id: 0,
            delay: Duration(seconds: 5),
            title: 't',
            body: 'b',
          ),
        ]);
        await scheduler.cancelAll();
      },
    );
  });
}
