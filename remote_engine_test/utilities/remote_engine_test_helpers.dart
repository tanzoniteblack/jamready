import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/scoreboard_state.dart';

/// Prints [message] prefixed with the elapsed time since the test process
/// started, so slow steps are easy to spot in CI/script output.
final _stopwatch = Stopwatch()..start();

void log(String message) {
  final ms = _stopwatch.elapsedMilliseconds;
  final seconds = (ms / 1000).toStringAsFixed(1);
  // ignore: avoid_print
  print('[+${seconds}s] $message');
}

/// Polls [condition] until it returns true or [timeout] elapses, logging how
/// long [label] took (or where it timed out).
///
/// Unlike the widget-test `pumpUntil` helper, this drives real wall-clock
/// time since there is no [WidgetTester] pumping a fake clock — the engine
/// under test is talking to a real, dockerized CRG server over a real
/// WebSocket connection.
Future<void> waitUntil(
  bool Function() condition, {
  required String label,
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 100),
  ScoreboardState? debugState,
}) async {
  final start = DateTime.now();
  final end = start.add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) {
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      log('waited ${elapsedMs}ms for: $label');
      return;
    }
    await Future.delayed(step);
  }
  if (!condition()) {
    log('TIMED OUT after ${timeout.inMilliseconds}ms waiting for: $label');
    if (debugState != null) log(dumpState(debugState));
    throw TestFailure('Timed out waiting for: $label');
  }
}

/// The CRG server's `GameImpl.quickClockControl()` treats two Start/Stop/
/// Timeout button presses within 1000ms of each other as an accidental
/// double-click: same button -> silently dropped; different button -> the
/// previous action is silently undone and replaced. There's no WS-visible
/// signal when this happens (no error, no rejected message), it just quietly
/// corrupts the game state. The app's real UI avoids this by enforcing
/// [JamControls.cooldownDuration] (3s) between taps; this test suite must do
/// the same for every Start/Stop/Timeout action since we call the engine
/// directly with no such client-side cooldown.
const clockActionCooldown = Duration(milliseconds: 1200);
DateTime? _lastClockActionTime;

/// Runs [action] (a startJam/stopJam/startTimeout/endTimeout call), waiting
/// first if needed so at least [clockActionCooldown] has elapsed since the
/// previous clock action — see [clockActionCooldown] for why this matters.
Future<void> clockAction(void Function() action) async {
  final last = _lastClockActionTime;
  if (last != null) {
    final elapsed = DateTime.now().difference(last);
    if (elapsed < clockActionCooldown) {
      await Future.delayed(clockActionCooldown - elapsed);
    }
  }
  action();
  _lastClockActionTime = DateTime.now();
}

/// Renders the fields most useful for diagnosing a stuck game-flow wait: the
/// clocks (time/running/number), the high-level game flags, and the current
/// labels the server is offering for the jam controls.
String dumpState(ScoreboardState state) {
  final clocks = state.clocks.entries
      .map((e) =>
          '${e.key}(time=${e.value.time}, running=${e.value.running}, number=${e.value.number})')
      .join(', ');
  return 'state snapshot: gameId=${state.gameId} inJam=${state.inJam} '
      'noMoreJam=${state.noMoreJam} inOvertime=${state.inOvertime} '
      'officialScore=${state.officialScore} periodCount=${state.periodCount} '
      'timeoutOwner=${state.timeoutOwner} officialReview=${state.officialReview} '
      'labelStart=${state.labelStart} labelStop=${state.labelStop} '
      'labelUndo=${state.labelUndo} clocks=[$clocks]';
}

String scoreboardHost() {
  const host = String.fromEnvironment('SCOREBOARD_HOST');
  return host.isNotEmpty ? host : '127.0.0.1';
}

int scoreboardPort() {
  const port = String.fromEnvironment('SCOREBOARD_PORT');
  return int.tryParse(port) ?? 8000;
}

String scoreboardVersion() {
  const version = String.fromEnvironment('SCOREBOARD_VERSION');
  return version; // empty string means unknown / not provided
}

/// Returns true if the scoreboard version is at least [major].[minor].
/// An unknown version (empty string) is treated as compatible.
bool versionAtLeast(String version, int major, int minor) {
  if (version.isEmpty) return true;
  final stripped = version.startsWith('v') ? version.substring(1) : version;
  final parts = stripped.split('.');
  final ma = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final mi = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return ma > major || (ma == major && mi >= minor);
}

Uri operatorWsUri(String host, int port) {
  final base = Uri.parse('ws://$host:$port');
  return base.replace(
    path: '/WS/',
    queryParameters: const {'source': 'remote_engine_test', 'platform': 'test'},
  );
}
