part of '../jam_timer_screen.dart';

extension _JamTimerLayout on _JamTimerScreenState {
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ScoreboardState state,
    Color alertColor,
  ) {
    return AppBar(
      title: Text(
        "JamReady",
        style: TextStyle(fontWeight: FontWeight.bold, color: alertColor),
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.home, color: Colors.white70),
        onPressed: () => _navigateToHome(context),
      ),
      actions: [
        if (_isLocalMode)
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: state.isConnected
                      ? Colors.green
                      : state.isConnecting
                      ? Colors.orange
                      : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
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
                    if (_isReadyToStart(state))
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
                    if (state.inTimeout)
                      _buildTimeoutTypeSection(state, isEnabled, scaleFactor)
                    else
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
                        enabled: isEnabled,
                        scaleFactor: scaleFactor,
                        jamClockNumber: state.clocks['Jam']?.number ?? 0,
                        lineupClockNumber: state.clocks['Lineup']?.number ?? 0,
                        onStartJam: () => _engine?.startJam(),
                        onStopJam: () => _engine?.stopJam(),
                        onTimeout: () => _engine?.startTimeout(),
                      ),

                    // Undo Section at bottom
                    SizedBox(height: 16 * scaleFactor),
                    _buildUndoSection(state, isEnabled),
                    SizedBox(height: 16 * scaleFactor),
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
}
