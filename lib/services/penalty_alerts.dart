import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';

/// A notification to show [delay] from now, while the app is backgrounded.
class PenaltyAlert {
  final int id;
  final Duration delay;
  final String title;
  final String body;

  const PenaltyAlert({
    required this.id,
    required this.delay,
    required this.title,
    required this.body,
  });

  @override
  String toString() => 'PenaltyAlert($id, $delay, $title, $body)';
}

/// Remaining time at which a seated skater should stand.
const standAt = Duration(seconds: 10);

/// How early alerts fire, so there is time to read one and act before the
/// moment it announces.
const alertLead = Duration(seconds: 2);

/// Alerts for every running seat in [state]: when the skater should stand and
/// when they are done. [jamMayStop] is true when the jam is controlled
/// elsewhere (CRG), so the alerts only hold if the jam keeps running.
List<PenaltyAlert> penaltyAlertsFor(
  PenaltyBoxState state, {
  bool jamMayStop = false,
}) {
  final caveat = jamMayStop ? ' if the jam is still running' : '';
  return state.seats.indexed
      .where(
        (e) =>
            e.$2.isOccupied &&
            e.$2.isRunning &&
            e.$2.timeRemaining > Duration.zero,
      )
      .expand((e) => _seatAlerts(state, e.$1, e.$2, caveat))
      .toList();
}

List<PenaltyAlert> _seatAlerts(
  PenaltyBoxState state,
  int seatIndex,
  SkaterSeat seat,
  String caveat,
) {
  final who = '${state.teamInfo(seat.teamIndex).name} #${seat.skaterNumber}';
  return [
    if (seat.timeRemaining > standAt)
      PenaltyAlert(
        id: seatIndex * 2,
        delay: _atLeastZero(seat.timeRemaining - standAt - alertLead),
        title: 'Stand $who',
        body: '10 seconds left$caveat.',
      ),
    PenaltyAlert(
      id: seatIndex * 2 + 1,
      delay: _atLeastZero(seat.timeRemaining - alertLead),
      title: 'Release $who',
      body: 'Penalty time is almost done$caveat.',
    ),
  ];
}

Duration _atLeastZero(Duration d) => d < Duration.zero ? Duration.zero : d;

/// Delivers [PenaltyAlert]s while the app is in the background.
abstract interface class PenaltyAlertScheduler {
  /// Replaces any pending alerts with [alerts].
  Future<void> schedule(List<PenaltyAlert> alerts);

  /// Removes pending and delivered alerts.
  Future<void> cancelAll();
}

/// [PenaltyAlertScheduler] backed by system notifications.
class NotificationAlertScheduler implements PenaltyAlertScheduler {
  NotificationAlertScheduler._();

  static final instance = NotificationAlertScheduler._();

  static const _exactAlarmAskedKey = 'penalty_alerts_exact_alarm_asked';

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _init;

  AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'penalty_timers',
      'Penalty timers',
      channelDescription: 'Stand and release alerts while JamReady is closed',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Sets up notifications and asks for permission to send them. Called at
  /// app launch; scheduling waits for it, so it is safe to call repeatedly.
  Future<void> init() => _init ??= _initialize();

  /// False under a test binding (unit or integration tests), where a
  /// permission prompt would cover the UI under test. Notifications are then
  /// treated as declined: nothing is requested or scheduled.
  static bool get _enabled => WidgetsBinding.instance is WidgetsFlutterBinding;

  Future<void> _initialize() async {
    if (!_enabled) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    final android = _android;
    if (android == null) return;
    await android.requestNotificationsPermission();
    await _askForExactAlarmsOnce(android);
  }

  /// Android 14+ denies exact alarms by default, and inexact alerts can be
  /// held back while the phone is idle. Send the user to the setting once;
  /// if they decline, alerts stay inexact and they are not asked again.
  Future<void> _askForExactAlarmsOnce(
    AndroidFlutterLocalNotificationsPlugin android,
  ) async {
    if (await android.canScheduleExactNotifications() ?? false) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_exactAlarmAskedKey) ?? false) return;
    await prefs.setBool(_exactAlarmAskedKey, true);
    await android.requestExactAlarmsPermission();
  }

  @override
  Future<void> schedule(List<PenaltyAlert> alerts) async {
    if (!_enabled) return;
    await init();
    await _plugin.cancelAll();
    // Checked each time: the user can change the setting at any point.
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    final now = tz.TZDateTime.now(tz.UTC);
    for (final alert in alerts) {
      await _plugin.zonedSchedule(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        scheduledDate: now.add(alert.delay),
        notificationDetails: _details,
        // Without the exact alarm permission Android may deliver late.
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_enabled) return;
    await init();
    await _plugin.cancelAll();
  }
}
