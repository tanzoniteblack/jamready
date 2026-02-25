part of '../jam_timer_screen.dart';

extension _JamTimerControls on _JamTimerScreenState {
  Widget _buildLocalModePeriodClock(
    ScoreboardState state,
    bool isEnabled,
    double scaleFactor,
  ) {
    final bool showIntermission = state.clocks['Intermission']!.running;
    final clock = showIntermission
        ? state.clocks['Intermission']!
        : state.clocks['Period']!;

    return ProminentPeriodClock(
      clock: clock,
      enabled: isEnabled,
      scaleFactor: scaleFactor,
      onAdjust: (delta) => _engine?.adjustClock(clock.name, delta),
      onSetTime: (timeMs) => _engine?.setClockTime(clock.name, timeMs),
    );
  }

  Widget _buildPeriodClockRow(ScoreboardState state, bool isEnabled) {
    final bool showIntermission = state.clocks['Intermission']!.running;
    final clock = showIntermission
        ? state.clocks['Intermission']!
        : state.clocks['Period']!;

    final String label = clock.displayName.isNotEmpty
        ? "${clock.displayName} ${clock.number}"
        : "${clock.name} ${clock.number}";

    final contentColor = isEnabled ? Colors.white70 : Colors.white24;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: showIntermission
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showIntermission
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.clockLabel.copyWith(
              color: contentColor,
              fontSize: 14,
            ),
          ),
          SizedBox(width: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatTime(clock.time),
              style: AppTextStyles.buttonText.copyWith(
                color: contentColor,
                fontSize: 18,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeoutTypeSection(
    ScoreboardState state,
    bool isEnabled,
    double scaleFactor,
  ) {
    final owner = state.timeoutOwner;
    final isOr = state.isOfficialReview;

    // For local mode, owner is '1' or '2', for remote it's a UUID
    final bool isTeam1TO = _isLocalMode
        ? (owner == '1' && !isOr)
        : (owner.isNotEmpty && owner == state.team1.serverId && !isOr);
    final bool isTeam2TO = _isLocalMode
        ? (owner == '2' && !isOr)
        : (owner.isNotEmpty && owner == state.team2.serverId && !isOr);
    final bool isOfficialTO = owner == "O";
    final bool isTeam1OR = _isLocalMode
        ? (owner == '1' && isOr)
        : (owner.isNotEmpty && owner == state.team1.serverId && isOr);
    final bool isTeam2OR = _isLocalMode
        ? (owner == '2' && isOr)
        : (owner.isNotEmpty && owner == state.team2.serverId && isOr);

    return Column(
      children: [
        // Official Timeout button
        _buildTimeoutButton(
          "OFFICIAL TIMEOUT",
          isActive: isOfficialTO,
          color: Colors.amber,
          enabled: isEnabled,
          height: 56 * scaleFactor,
          onTap: () => _engine?.setTimeoutOwner('O'),
          scaleFactor: scaleFactor,
        ),

        SizedBox(height: 16 * scaleFactor),

        // Team timeout/review rows
        Row(
          children: [
            // Team 1 column
            Expanded(
              child: Column(
                children: [
                  Text(
                    state.team1.displayName,
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 14 * scaleFactor,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 10 * scaleFactor),
                  _buildTimeoutButton(
                    "TIMEOUT",
                    isActive: isTeam1TO,
                    count: state.team1.timeouts,
                    color: Colors.white,
                    enabled: isEnabled,
                    height: 48 * scaleFactor,
                    onTap: () => _engine?.setTimeoutOwner('1'),
                    scaleFactor: scaleFactor,
                  ),
                  SizedBox(height: 8 * scaleFactor),
                  _buildTimeoutButton(
                    "REVIEW",
                    isActive: isTeam1OR,
                    count: state.team1.officialReviews,
                    color: Colors.blue.shade300,
                    enabled: isEnabled,
                    height: 48 * scaleFactor,
                    onTap: () =>
                        _engine?.setTimeoutOwner('1', isOfficialReview: true),
                    scaleFactor: scaleFactor,
                  ),
                ],
              ),
            ),
            SizedBox(width: 12 * scaleFactor),
            // Team 2 column
            Expanded(
              child: Column(
                children: [
                  Text(
                    state.team2.displayName,
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 14 * scaleFactor,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 10 * scaleFactor),
                  _buildTimeoutButton(
                    "TIMEOUT",
                    isActive: isTeam2TO,
                    count: state.team2.timeouts,
                    color: Colors.white,
                    enabled: isEnabled,
                    height: 48 * scaleFactor,
                    onTap: () => _engine?.setTimeoutOwner('2'),
                    scaleFactor: scaleFactor,
                  ),
                  SizedBox(height: 8 * scaleFactor),
                  _buildTimeoutButton(
                    "REVIEW",
                    isActive: isTeam2OR,
                    count: state.team2.officialReviews,
                    color: Colors.blue.shade300,
                    enabled: isEnabled,
                    height: 48 * scaleFactor,
                    onTap: () =>
                        _engine?.setTimeoutOwner('2', isOfficialReview: true),
                    scaleFactor: scaleFactor,
                  ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: 20 * scaleFactor),

        // End Timeout button
        _buildEndTimeoutButton(isEnabled, scaleFactor),
      ],
    );
  }

  Widget _buildTimeoutButton(
    String label, {
    required bool isActive,
    int? count,
    required Color color,
    required bool enabled,
    required double height,
    required VoidCallback onTap,
    double scaleFactor = 1.0,
  }) {
    final bool useDarkText =
        isActive && (color == Colors.amber || color.computeLuminance() > 0.5);
    final textColor = useDarkText ? Colors.black87 : Colors.white;

    final highlightColor = Color.lerp(color, Colors.white, 0.08)!;
    final shadowColor = Color.lerp(color, Colors.black, 0.12)!;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12 * scaleFactor),
          boxShadow: enabled && isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 4 * scaleFactor,
                    offset: Offset(0, 2 * scaleFactor),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12 * scaleFactor),
            child: Ink(
              decoration: BoxDecoration(
                gradient: isActive && enabled
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [highlightColor, color, shadowColor],
                        stops: const [0.0, 0.5, 1.0],
                      )
                    : null,
                color: isActive ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12 * scaleFactor),
                border: Border.all(
                  color: isActive ? color : Colors.white30,
                  width: (isActive ? 2 : 1) * scaleFactor,
                ),
              ),
              child: Container(
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: 8 * scaleFactor),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: enabled
                              ? (isActive ? textColor : Colors.white)
                              : Colors.white38,
                          fontSize: 14 * scaleFactor,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (count != null) ...[
                      SizedBox(width: 6 * scaleFactor),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8 * scaleFactor,
                          vertical: 2 * scaleFactor,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (useDarkText
                                    ? Colors.black.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.2))
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10 * scaleFactor),
                        ),
                        child: Text(
                          "$count",
                          style: TextStyle(
                            color: enabled
                                ? (isActive ? textColor : Colors.white)
                                : Colors.white38,
                            fontSize: 14 * scaleFactor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndTimeoutButton(bool isEnabled, double scaleFactor) {
    final color = Colors.red.shade700;
    final highlightColor = Color.lerp(color, Colors.white, 0.1)!;
    final shadowColor = Color.lerp(color, Colors.black, 0.15)!;

    return SizedBox(
      width: double.infinity,
      height: 72 * scaleFactor,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16 * scaleFactor),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4 * scaleFactor,
                    offset: Offset(0, 2 * scaleFactor),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isEnabled ? () => _engine?.endTimeout() : null,
            borderRadius: BorderRadius.circular(16 * scaleFactor),
            child: Ink(
              decoration: BoxDecoration(
                gradient: isEnabled
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [highlightColor, color, shadowColor],
                        stops: const [0.0, 0.5, 1.0],
                      )
                    : null,
                color: isEnabled ? null : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(16 * scaleFactor),
              ),
              child: Container(
                alignment: Alignment.center,
                child: Text(
                  "END TIMEOUT",
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 24 * scaleFactor,
                    color: isEnabled ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadyToStartDisplay(
    ScoreboardState state,
    bool isEnabled,
    double scaleFactor,
    Color alertColor,
  ) {
    final periodNumber = (state.clocks['Period']?.number ?? 1);
    final color = isEnabled ? alertColor : Colors.white12;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 24 * scaleFactor,
        vertical: 12 * scaleFactor,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            periodNumber == 0 ? "GAME" : "PERIOD $periodNumber",
            style: AppTextStyles.clockLabel.copyWith(
              fontSize: 18 * scaleFactor,
              color: color,
              height: 1.0,
            ),
          ),
          Text(
            "READY",
            style: AppTextStyles.clockTime.copyWith(
              color: color,
              fontSize: 72 * scaleFactor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUndoSection(ScoreboardState state, bool isEnabled) {
    final hasUndoAction = state.hasUndoAction;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SwipeButton(
        label: hasUndoAction ? state.labelUndo : "No Undo Available",
        enabled: isEnabled && hasUndoAction,
        color: const Color(0xFF455A64),
        compact: true,
        onConfirmed: () {
          _engine?.undo();
        },
      ),
    );
  }
}
