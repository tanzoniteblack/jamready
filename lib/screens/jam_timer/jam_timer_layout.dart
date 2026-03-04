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
    final controlsEnabled = isEnabled &&
        !_isGameOver(state) &&
        !_isHalftimeIntermission(state) &&
        !(_isUnofficialScore(state) && state.noMoreJam);
    final timeoutRunning = state.clocks['Timeout']?.running ?? false;
    final lineupRunning = state.clocks['Lineup']?.running ?? false;
    final inOverlapTimeoutState = timeoutRunning && (state.inJam || lineupRunning);
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
