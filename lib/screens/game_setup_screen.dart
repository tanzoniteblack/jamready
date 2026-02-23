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

  final List<Ruleset> _rulesets = [
    Ruleset.wftda(),
    Ruleset.rdcl(),
  ];

  Ruleset get _selectedRuleset =>
      _rulesets.firstWhere((r) => r.id == _selectedRulesetId);

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
      backgroundColor: const Color(0xFF121212),
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
        children: _rulesets.map((ruleset) {
          final isSelected = ruleset.id == _selectedRulesetId;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedRulesetId = ruleset.id),
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
                    ruleset.name,
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
    final ruleset = _selectedRuleset;
    final periodMinutes = ruleset.periodDurationMs ~/ 60000;
    final jamSeconds = ruleset.jamDurationMs ~/ 1000;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildDetailItem(
              "${ruleset.periodCount}x${periodMinutes}min", "Periods"),
          _buildDetailItem("${jamSeconds}s", "Jams"),
          _buildDetailItem("${ruleset.timeoutsPerGame}", "Timeouts"),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
      ],
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
