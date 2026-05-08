part of '../jam_timer_screen.dart';

extension _JamTimerLayout on _JamTimerScreenState {
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ScoreboardState state,
    Color alertColor,
  ) {
    final connectionColor = state.isConnected
        ? Colors.green
        : state.isConnecting
        ? Colors.orange
        : Colors.red;

    return AppBar(
      toolbarHeight: _isLocalMode ? 62 : 74,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(alertColor, Colors.white, 0.2)!,
                Color.lerp(alertColor, Colors.black, 0.12)!,
              ],
            ).createShader(bounds),
            child: Text(
              "JamReady",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.4,
                fontSize: 24,
              ),
            ),
          ),
          if (!_isLocalMode)
            Text(
              state.isConnected ? "Connected to Scoreboard" : "Remote Mode",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
        ],
      ),
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: Align(
        alignment: Alignment.bottomCenter,
        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
      ),
      leading: IconButton(
        icon: Icon(Icons.home_rounded, color: Colors.white70),
        onPressed: () => _navigateToHome(context),
      ),
      actions: [
        IconButton(
          tooltip: 'Jam timer signals',
          onPressed: () => _openProcedureHelper(context),
          icon: const _WhistleHelpIcon(),
        ),
        if (_isLocalMode)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phonelink_off, color: Colors.orange, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'LOCAL',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: connectionColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                state.isConnected
                    ? "LIVE"
                    : state.isConnecting
                    ? "CONNECTING"
                    : "OFFLINE",
                style: TextStyle(
                  color: connectionColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(ScoreboardState state, bool isEnabled, Color alertColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final scaleFactor = availableHeight < 600
            ? (availableHeight / 600).clamp(0.7, 1.0)
            : availableHeight > 800
            ? (1.0 + (availableHeight - 800) / 1000 * 0.15).clamp(1.0, 1.15)
            : 1.0;
        final isCompact = availableHeight < 550;

        final scrollView = SingleChildScrollView(
          physics: _isLocalMode
              ? const ClampingScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: isCompact ? 8.0 : 16.0,
                ),
                child: Column(
                  children: [
                    // Teams - fixed at top
                    Row(
                      children: [
                        Expanded(
                          child: TeamPanel(
                            team: state.team1,
                            isLeft: true,
                            enabled: isEnabled,
                            onRetainedToggle: (val) =>
                                _engine?.setRetainedReview(1, val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TeamPanel(
                            team: state.team2,
                            isLeft: false,
                            enabled: isEnabled,
                            onRetainedToggle: (val) =>
                                _engine?.setRetainedReview(2, val),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: isCompact ? 8 : 16),

                    // Period / Intermission Clock
                    if (_isLocalMode)
                      _buildLocalModePeriodClock(state, isEnabled, scaleFactor)
                    else if (!(state.clocks['Intermission']?.running ?? false))
                      _buildPeriodClockRow(state, isEnabled),

                    if (_isLocalMode ||
                        !(state.clocks['Intermission']?.running ?? false))
                      SizedBox(height: isCompact ? 12 : 20),

                    const Spacer(),

                    // Active Game Clock or Ready indicator
                    if (_isGameOver(state))
                      _buildGameOverDisplay(isEnabled, scaleFactor)
                    else if (_isUnofficialScore(state))
                      _buildUnofficialScoreDisplay(isEnabled, scaleFactor)
                    else if (_isPreGameCountdown(state))
                      _buildTimeToDerbyDisplay(
                        state,
                        isEnabled,
                        scaleFactor,
                        alertColor,
                      )
                    else if (_isReadyToStart(state))
                      _buildReadyToStartDisplay(
                        state,
                        isEnabled,
                        scaleFactor,
                        alertColor,
                      )
                    else
                      ClockDisplay(
                        clock: _determineActiveClock(state),
                        textColor: alertColor,
                        enabled: isEnabled,
                        scaleFactor: scaleFactor,
                        onAdjust: (val) {
                          final active = _determineActiveClock(state);
                          final delta = int.tryParse(val) ?? 0;
                          _engine?.adjustClock(active.name, delta);
                        },
                        onSetTime: _isLocalMode
                            ? (timeMs) {
                                final active = _determineActiveClock(state);
                                _engine?.setClockTime(active.name, timeMs);
                              }
                            : null,
                      ),

                    // Flexible spacer pushes controls toward bottom
                    const Spacer(),
                    const Spacer(),
                    const Spacer(),

                    // Timeout Type Buttons OR normal controls
                    _buildControlDeck(
                      state,
                      isEnabled,
                      scaleFactor,
                      alertColor,
                    ),

                    SizedBox(height: 12 * scaleFactor),
                  ],
                ),
              ),
            ),
          ),
        );

        // Wrap with RefreshIndicator for remote mode
        if (!_isLocalMode) {
          return RefreshIndicator(
            onRefresh: () async {
              await _connectToServer(forceReconnect: true);
            },
            child: scrollView,
          );
        }

        return scrollView;
      },
    );
  }

  Widget _buildControlDeck(
    ScoreboardState state,
    bool isEnabled,
    double scaleFactor,
    Color alertColor,
  ) {
    // Disable controls when the game is officially over, during active
    // halftime intermission, or during unofficial score with no remaining
    // jams (noMoreJam=false means overtime is still possible, so keep live).
    final controlsEnabled =
        isEnabled &&
        !_isGameOver(state) &&
        !_isHalftimeIntermission(state) &&
        !(_isUnofficialScore(state) && state.noMoreJam);
    final timeoutRunning = state.clocks['Timeout']?.running ?? false;
    final lineupRunning = state.clocks['Lineup']?.running ?? false;
    final inOverlapTimeoutState =
        timeoutRunning && (state.inJam || lineupRunning);
    final showTimeoutOnly = timeoutRunning && !inOverlapTimeoutState;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        12 * scaleFactor,
        12 * scaleFactor,
        12 * scaleFactor,
        10 * scaleFactor,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(20 * scaleFactor),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 14 * scaleFactor,
            offset: Offset(0, 6 * scaleFactor),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_isUnofficialScore(state) &&
              (_isLocalMode ||
                  state.labelStop.toLowerCase().contains('overtime')))
            _buildOvertimeDecisionSection(state, isEnabled, scaleFactor)
          else if (showTimeoutOnly)
            _buildTimeoutTypeSection(state, controlsEnabled, scaleFactor)
          else ...[
            JamControls(
              inJam: state.inJam,
              isPrePeriod: _isPrePeriod(state),
              isIntermission:
                  (state.clocks['Intermission']?.running ?? false) ||
                  (state.clocks['Period']?.number == 0),
              startLabel: state.labelStart,
              stopLabel: state.labelStop,
              timeoutLabel: state.labelTimeout,
              alertColor: alertColor,
              enabled: controlsEnabled,
              scaleFactor: scaleFactor,
              jamClockNumber: state.clocks['Jam']?.number ?? 0,
              lineupClockNumber: state.clocks['Lineup']?.number ?? 0,
              onStartJam: () => _engine?.startJam(),
              onStopJam: () => _engine?.stopJam(),
              onTimeout: () => _engine?.startTimeout(),
            ),
            if (inOverlapTimeoutState) ...[
              SizedBox(height: 16 * scaleFactor),
              _buildTimeoutTypeSection(state, controlsEnabled, scaleFactor),
            ],
          ],
          SizedBox(height: 10 * scaleFactor),
          _buildUndoSection(state, controlsEnabled),
        ],
      ),
    );
  }
}

class _WhistleHelpIcon extends StatelessWidget {
  const _WhistleHelpIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WhistleIconPainter(color: Colors.white70),
            ),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 15,
              height: 15,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.orange.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF121212), width: 1.5),
              ),
              child: const Text(
                '?',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhistleIconPainter extends CustomPainter {
  final Color color;

  const _WhistleIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // GiWhistle from react-icons/game-icons.net, CC Attribution.
    final icon = _giWhistlePath();
    final bounds = icon.getBounds();
    final scale =
        (size.shortestSide * 0.82) /
        (bounds.width > bounds.height ? bounds.width : bounds.height);
    final dx = (size.width - bounds.width * scale) / 2 - bounds.left * scale;
    final dy = (size.height - bounds.height * scale) / 2 - bounds.top * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawPath(
      icon,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  Path _giWhistlePath() {
    return Path()
      ..moveTo(93.75, 81.443)
      ..relativeCubicTo(-5.38, 0, -12.368, 2.49, -22.358, 8.967)
      ..relativeCubicTo(3.966, 4.682, 8.167, 9.687, 16.47, 19.256)
      ..relativeCubicTo(5.782, 6.663, 11.618, 13.29, 16.026, 18.088)
      ..relativeCubicTo(0.038, 0.042, 0.055, 0.055, 0.092, 0.096)
      ..relativeLineTo(30.894, -17.932)
      ..relativeLineTo(-14.652, -14.148)
      ..relativeCubicTo(-11.292, -9.404, -18.644, -13.866, -25.418, -14.293)
      ..relativeCubicTo(-0.345, -0.022, -0.696, -0.034, -1.055, -0.034)
      ..close()
      ..moveTo(213.83, 96.525)
      ..relativeCubicTo(-0.885, -0.01, -1.767, -0.006, -2.643, 0.01)
      ..relativeCubicTo(-10.46, 0.193, -20.2, 2.23, -26.742, 5.424)
      ..relativeLineTo(-67.262, 39.038)
      ..relativeCubicTo(2.45, 0.544, 4.885, 1.196, 7.287, 2.02)
      ..relativeCubicTo(17.275, 5.923, 33.093, 18.223, 49.568, 34.7)
      ..relativeLineTo(216.44, 213.5)
      ..relativeLineTo(80.978, -44.433)
      ..lineTo(258.54, 111.38)
      ..relativeCubicTo(-8.656, -7.84, -22.49, -12.908, -36.693, -14.394)
      ..relativeCubicTo(-2.677, -0.28, -5.363, -0.43, -8.018, -0.46)
      ..close()
      ..moveTo(58.192, 102.74)
      ..relativeCubicTo(-17.543, 20.723, -20.57, 37.186, -15.326, 57.004)
      ..relativeCubicTo(0.692, 2.618, 3.057, 6.357, 6.373, 10.47)
      ..relativeCubicTo(2.195, -3.144, 4.55, -6.304, 7.086, -9.478)
      ..relativeCubicTo(3.99, -4.995, 8.385, -9.183, 13.085, -12.558)
      ..relativeLineTo(-0.106, -0.2)
      ..relativeLineTo(2.768, -1.61)
      ..relativeCubicTo(1.354, -0.862, 2.73, -1.66, 4.13, -2.393)
      ..relativeLineTo(11.868, -6.89)
      ..relativeCubicTo(-4.175, -4.618, -8.94, -10.017, -13.803, -15.622)
      ..relativeCubicTo(-5.956, -6.864, -11.732, -13.62, -16.074, -18.723)
      ..close()
      ..moveTo(242.285, 116.178)
      ..relativeLineTo(58.415, 61.67)
      ..relativeCubicTo(-46.086, -5.037, -56.79, 13.2, -69.027, 34.2)
      ..relativeLineTo(-57.334, -59.304)
      ..relativeLineTo(67.946, -36.566)
      ..close()
      ..moveTo(103.702, 157.23)
      ..relativeCubicTo(-0.714, -0.016, -1.43, -0.016, -2.15, 0.002)
      ..relativeCubicTo(-6.976, 0.18, -14.207, 2.058, -22.252, 5.885)
      ..relativeCubicTo(-3.035, 2.29, -5.99, 5.196, -8.91, 8.852)
      ..relativeCubicTo(-25.77, 32.264, -30.45, 59.135, -25.484, 83.477)
      ..relativeCubicTo(4.965, 24.343, 20.536, 46.656, 37.916, 66.455)
      ..relativeCubicTo(13.314, 15.168, 28.86, 23.992, 48.472, 27.93)
      ..relativeCubicTo(19.614, 3.94, 43.438, 2.708, 71.98, -3.475)
      ..relativeCubicTo(33.246, -7.2, 66.01, 8.42, 95.81, 27.665)
      ..relativeCubicTo(26.118, 16.868, 50.676, 37.09, 70.98, 49.95)
      ..relativeLineTo(8.79, -18.935)
      ..relativeLineTo(-217.52, -214.57)
      ..relativeLineTo(-0.022, -0.022)
      ..relativeCubicTo(-15.524, -15.524, -29.565, -25.905, -42.682, -30.402)
      ..relativeCubicTo(-5.02, -1.722, -9.925, -2.695, -14.928, -2.813)
      ..close()
      ..moveTo(470.782, 367.686)
      ..relativeLineTo(-73.45, 40.304)
      ..relativeLineTo(-10.48, 22.567)
      ..relativeLineTo(70.833, -38.41)
      ..relativeLineTo(13.096, -24.46)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _WhistleIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
