import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_config.dart';
import '../models/ruleset.dart';
import '../models/scoreboard_state.dart';
import '../services/local_game_engine.dart';
import '../styles/text_styles.dart';
import 'jam_timer_screen.dart';

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  String _selectedRulesetId = 'wftda';
  final _team1Controller = TextEditingController(text: 'Salt');
  final _team2Controller = TextEditingController(text: 'Pepper');

  // Custom ruleset parameters (null means use base ruleset value)
  int? _customPeriodCount;
  int? _customPeriodDurationMinutes;
  int? _customJamDurationSeconds;
  bool _isCustomizing = false;

  final Map<String, Ruleset> _baseRulesets = {
    'wftda': Ruleset.wftda(),
    'rdcl': Ruleset.rdcl(),
  };

  Ruleset get _baseRuleset => _baseRulesets[_selectedRulesetId]!;

  Ruleset get _selectedRuleset {
    final base = _baseRuleset;
    if (_customPeriodCount == null &&
        _customPeriodDurationMinutes == null &&
        _customJamDurationSeconds == null) {
      return base;
    }

    // Create custom ruleset with modified values
    return base.copyWith(
      id: 'custom_${base.id}',
      isBuiltIn: false,
      periodCount: _customPeriodCount ?? base.periodCount,
      periodDurationMs: _customPeriodDurationMinutes != null
          ? _customPeriodDurationMinutes! * 60 * 1000
          : base.periodDurationMs,
      jamDurationMs: _customJamDurationSeconds != null
          ? _customJamDurationSeconds! * 1000
          : base.jamDurationMs,
    );
  }

  void _selectRuleset(String id) {
    setState(() {
      _selectedRulesetId = id;
      // Reset custom values when changing base ruleset
      _customPeriodCount = null;
      _customPeriodDurationMinutes = null;
      _customJamDurationSeconds = null;
      _isCustomizing = false;
    });
  }

  bool get _hasCustomValues =>
      _customPeriodCount != null ||
      _customPeriodDurationMinutes != null ||
      _customJamDurationSeconds != null;

  void _resetCustomValues() {
    setState(() {
      _customPeriodCount = null;
      _customPeriodDurationMinutes = null;
      _customJamDurationSeconds = null;
      _isCustomizing = false;
    });
  }

  @override
  void dispose() {
    _team1Controller.dispose();
    _team2Controller.dispose();
    super.dispose();
  }

  void _startGame() {
    final config = GameConfig(
      ruleset: _selectedRuleset,
      team1Name: _team1Controller.text.trim().isEmpty
          ? 'Salt'
          : _team1Controller.text.trim(),
      team2Name: _team2Controller.text.trim().isEmpty
          ? 'Pepper'
          : _team2Controller.text.trim(),
    );

    final state = Provider.of<ScoreboardState>(context, listen: false);
    final engine = LocalGameEngine(state, config);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => JamTimerScreen(engine: engine),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        title: Text("NEW GAME", style: AppTextStyles.appBarTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ruleset section
            Text(
              "RULESET",
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white70,
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            _buildRulesetSelector(),
            const SizedBox(height: 8),
            _buildRulesetDetails(),

            const SizedBox(height: 32),

            // Teams section
            Text(
              "TEAMS",
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white70,
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTeamInput(_team1Controller, "Team 1", "Salt"),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTeamInput(_team2Controller, "Team 2", "Pepper"),
                ),
              ],
            ),

            const Spacer(),

            // Start button
            SizedBox(
              height: 64,
              child: ElevatedButton(
                onPressed: _startGame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  "START GAME",
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesetSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: _baseRulesets.entries.map((entry) {
          final isSelected = entry.key == _selectedRulesetId;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectRuleset(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: isSelected
                      ? Border.all(color: Colors.orange, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    entry.value.name,
                    style: AppTextStyles.buttonText.copyWith(
                      color: isSelected ? Colors.orange : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRulesetDetails() {
    final base = _baseRuleset;
    final ruleset = _selectedRuleset;
    final periodMinutes = ruleset.periodDurationMs ~/ 60000;
    final jamSeconds = ruleset.jamDurationMs ~/ 1000;

    final isCustom = _hasCustomValues;
    final borderColor = isCustom
        ? Colors.orange.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.08);
    final bgColor = isCustom
        ? Colors.orange.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.03);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          // Summary row - always visible, compact
          _buildSummaryRow(ruleset, periodMinutes, jamSeconds),

          // Customize toggle
          const SizedBox(height: 12),
          _buildCustomizeToggle(),

          // Editable fields - shown when customizing
          if (_isCustomizing) ...[
            const SizedBox(height: 16),
            _buildEditableFields(base, ruleset, periodMinutes, jamSeconds),
          ],

          // Reset button when customized
          if (isCustom && !_isCustomizing) ...[
            const SizedBox(height: 8),
            _buildResetButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(Ruleset ruleset, int periodMinutes, int jamSeconds) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSummaryChip(
          "${ruleset.periodCount}×${periodMinutes}min",
          "periods",
          _customPeriodCount != null || _customPeriodDurationMinutes != null,
        ),
        Container(
          width: 1,
          height: 24,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        _buildSummaryChip(
          "${jamSeconds}s",
          "jams",
          _customJamDurationSeconds != null,
        ),
        Container(
          width: 1,
          height: 24,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        _buildSummaryChip(
          "${ruleset.timeoutsPerGame}",
          "timeouts",
          false,
        ),
      ],
    );
  }

  Widget _buildSummaryChip(String value, String label, bool isModified) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTextStyles.clockLabel.copyWith(
            color: isModified ? Colors.orange : Colors.white,
            fontSize: 14,
            fontWeight: isModified ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white38,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomizeToggle() {
    return GestureDetector(
      onTap: () => setState(() => _isCustomizing = !_isCustomizing),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isCustomizing
              ? Colors.orange.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isCustomizing
                ? Colors.orange.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isCustomizing ? Icons.tune : Icons.tune_outlined,
              size: 16,
              color: _isCustomizing ? Colors.orange : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              _isCustomizing ? "CUSTOMIZING" : "CUSTOMIZE",
              style: TextStyle(
                color: _isCustomizing ? Colors.orange : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isCustomizing
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 16,
              color: _isCustomizing ? Colors.orange : Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableFields(
      Ruleset base, Ruleset ruleset, int periodMinutes, int jamSeconds) {
    return Column(
      children: [
        // Period count
        _buildEditableRow(
          label: "Number of periods",
          value: "${ruleset.periodCount}",
          isModified: _customPeriodCount != null,
          onDecrement: () => setState(() {
            _customPeriodCount =
                (_customPeriodCount ?? base.periodCount) - 1;
            if (_customPeriodCount! < 1) _customPeriodCount = 1;
          }),
          onIncrement: () => setState(() {
            _customPeriodCount =
                (_customPeriodCount ?? base.periodCount) + 1;
            if (_customPeriodCount! > 10) _customPeriodCount = 10;
          }),
        ),
        const SizedBox(height: 8),
        // Period duration
        _buildEditableRow(
          label: "Period length",
          value: "$periodMinutes min",
          isModified: _customPeriodDurationMinutes != null,
          onDecrement: () => setState(() {
            _customPeriodDurationMinutes = (_customPeriodDurationMinutes ??
                    base.periodDurationMs ~/ 60000) -
                5;
            if (_customPeriodDurationMinutes! < 5) {
              _customPeriodDurationMinutes = 5;
            }
          }),
          onIncrement: () => setState(() {
            _customPeriodDurationMinutes = (_customPeriodDurationMinutes ??
                    base.periodDurationMs ~/ 60000) +
                5;
            if (_customPeriodDurationMinutes! > 60) {
              _customPeriodDurationMinutes = 60;
            }
          }),
        ),
        const SizedBox(height: 8),
        // Jam duration
        _buildEditableRow(
          label: "Jam length",
          value: "$jamSeconds sec",
          isModified: _customJamDurationSeconds != null,
          onDecrement: () => setState(() {
            _customJamDurationSeconds =
                (_customJamDurationSeconds ?? base.jamDurationMs ~/ 1000) - 15;
            if (_customJamDurationSeconds! < 30) {
              _customJamDurationSeconds = 30;
            }
          }),
          onIncrement: () => setState(() {
            _customJamDurationSeconds =
                (_customJamDurationSeconds ?? base.jamDurationMs ~/ 1000) + 15;
            if (_customJamDurationSeconds! > 180) {
              _customJamDurationSeconds = 180;
            }
          }),
        ),
      ],
    );
  }

  Widget _buildEditableRow({
    required String label,
    required String value,
    required bool isModified,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isModified ? Colors.orange : Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        _buildCompactButton(Icons.remove, onDecrement),
        Container(
          width: 64,
          alignment: Alignment.center,
          child: Text(
            value,
            style: TextStyle(
              color: isModified ? Colors.orange : Colors.white,
              fontSize: 14,
              fontWeight: isModified ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        _buildCompactButton(Icons.add, onIncrement),
      ],
    );
  }

  Widget _buildCompactButton(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        color: Colors.white70,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: _resetCustomValues,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restore, size: 12, color: Colors.orange),
          const SizedBox(width: 4),
          Text(
            "Reset to ${_baseRuleset.name} defaults",
            style: TextStyle(
              color: Colors.orange,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamInput(
      TextEditingController controller, String label, String hint) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
