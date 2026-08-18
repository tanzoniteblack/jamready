import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../services/local_penalty_engine.dart';
import '../services/penalty_engine.dart';
import '../services/remote_penalty_engine.dart';
import '../styles/background.dart';
import '../styles/text_styles.dart';
import 'box_timer/timer_view_host.dart';
import 'home/qr_scanner_screen.dart';
import 'home/role_selector.dart';
import 'home/shared_helpers.dart';
import 'home/team_settings.dart';

class PenaltyBoxHomeScreen extends StatefulWidget {
  const PenaltyBoxHomeScreen({super.key});

  @override
  State<PenaltyBoxHomeScreen> createState() => _PenaltyBoxHomeScreenState();
}

class _PenaltyBoxHomeScreenState extends State<PenaltyBoxHomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  bool _isLoading = false;

  // Phase 2 state
  bool _showRoleSelector = false;
  PenaltyEngine? _previewEngine;
  PenaltyBoxState? _previewState;
  PenaltyEngine? _activeEngine;
  String _team1Name = 'Salt';
  String _team2Name = 'Pepper';
  Timer? _teamNameTimer;
  VoidCallback? _teamNameListener;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('jambox_host') ?? '10.0.2.2';
      _portController.text = prefs.getString('jambox_port') ?? '8000';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jambox_host', _hostController.text.trim());
    await prefs.setString('jambox_port', _portController.text.trim());
  }

  Future<void> _connectAndFetchTeams() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    await _saveSettings();
    _disposePreview();

    final state = PenaltyBoxState();
    final engine = RemotePenaltyEngine(state);
    _previewState = state;
    _previewEngine = engine;

    final url =
        'http://${_hostController.text.trim()}:${_portController.text.trim()}';
    engine.connect(url);

    // Listen for team names to arrive, with a 3-second timeout fallback
    _teamNameListener = () {
      if (state.teamNamesFromRemote) {
        _advanceToRoleSelector(state.team1.name, state.team2.name);
      }
    };
    state.addListener(_teamNameListener!);
    _teamNameTimer = Timer(
      const Duration(seconds: 3),
      () => _advanceToRoleSelector(
        _previewState?.team1.name ?? 'Salt',
        _previewState?.team2.name ?? 'Pepper',
      ),
    );

    if (mounted) setState(() => _isLoading = false);
  }

  void _advanceToRoleSelector(String t1, String t2) {
    _teamNameTimer?.cancel();
    _teamNameTimer = null;
    if (_teamNameListener != null) {
      _previewState?.removeListener(_teamNameListener!);
      _teamNameListener = null;
    }
    if (!mounted) return;
    setState(() {
      _team1Name = t1.isNotEmpty ? t1 : 'Salt';
      _team2Name = t2.isNotEmpty ? t2 : 'Pepper';
      _showRoleSelector = true;
    });
  }

  Future<void> _goOffline() async {
    await _saveSettings();
    _disposePreview();

    final state = PenaltyBoxState();
    final engine = LocalPenaltyEngine(state);
    await engine.initialize();

    _previewState = state;
    _previewEngine = engine;
    _attachTeamNameListener(state);

    if (!mounted) return;
    setState(() {
      _team1Name = 'Salt';
      _team2Name = 'Pepper';
      _showRoleSelector = true;
    });
  }

  void _attachTeamNameListener(PenaltyBoxState state) {
    state.addListener(() {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _team1Name = state.team1.name;
              _team2Name = state.team2.name;
            });
          }
        });
      }
    });
  }

  void _resetConnection() {
    _disposePreview();
    setState(() {
      _showRoleSelector = false;
      _team1Name = 'Salt';
      _team2Name = 'Pepper';
    });
  }

  void _disposePreview() {
    _teamNameTimer?.cancel();
    _teamNameTimer = null;
    if (_teamNameListener != null) {
      _previewState?.removeListener(_teamNameListener!);
      _teamNameListener = null;
    }
    _previewEngine?.dispose();
    _previewEngine = null;
    _previewState = null;
  }

  Future<void> _startGame(AppRole role) async {
    final teamIdx = switch (role) {
      AppRole.team1BlockersOnly || AppRole.team1Full => 1,
      AppRole.team2Full || AppRole.team2BlockersOnly => 2,
      _ => null,
    };

    PenaltyBoxState state;
    PenaltyEngine engine;

    // Reuse the preview engine/state
    state = _previewState!;
    state.role = role;
    state.teamIndex = teamIdx;
    engine = _previewEngine!;

    // Clear references so dispose() doesn't shut it down.
    _previewEngine = null;
    _previewState = null;

    _activeEngine = engine;

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: TimerViewHost(engine: engine),
        ),
      ),
    );

    // Returned from game screen — restore engine so user can re-enter
    if (mounted && _activeEngine != null) {
      final returned = _activeEngine!;
      _activeEngine = null;
      setState(() {
        _previewEngine = returned;
        _previewState = returned.state;
        _team1Name = returned.state.team1.name;
        _team2Name = returned.state.team2.name;
        _showRoleSelector = true;
      });

      // Re-attach listener for offline mode to keep team names in sync
      if (_previewEngine?.isLocal == true && _previewState != null) {
        _attachTeamNameListener(_previewState!);
      }
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QRScannerScreen()));
    if (result != null && mounted) {
      _parseAddress(result);
    }
  }

  void _parseAddress(String scannedValue) {
    String value = scannedValue.trim();
    if (value.startsWith('http://')) value = value.substring(7);
    if (value.startsWith('https://')) value = value.substring(8);
    final pathIndex = value.indexOf('/');
    if (pathIndex != -1) value = value.substring(0, pathIndex);
    final parts = value.split(':');
    if (parts.isNotEmpty) {
      setState(() {
        _hostController.text = parts[0];
        _portController.text = parts.length > 1 ? parts[1] : '8000';
      });
    }
  }

  @override
  void dispose() {
    _activeEngine?.dispose();
    _activeEngine = null;
    _disposePreview();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicBackground(
      accentColor: Colors.deepOrange.shade400,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          toolbarHeight: 78,
          titleSpacing: 16,
          title: Text('JamBox', style: AppTextStyles.appBarTitle),
          centerTitle: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: _showRoleSelector
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: _resetConnection,
                )
              : null,
          flexibleSpace: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Phase 1: Connection (hidden once role selector is shown) ──
                if (!_showRoleSelector) ...[
                  Text(
                    'REMOTE SCOREBOARD',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect to sync with CRG scoreboard.',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _scanQRCode,
                      icon: const Icon(Icons.qr_code_scanner, size: 22),
                      label: Text(
                        'SCAN SCOREBOARD QR',
                        style: AppTextStyles.buttonText.copyWith(fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  divider('OR ENTER MANUALLY'),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _hostController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      'Host / IP Address',
                      'e.g. 192.168.1.100',
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Enter a host address'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _portController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Port', 'e.g. 8000'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter a port';
                      if (int.tryParse(v) == null) {
                        return 'Port must be a number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _connectAndFetchTeams,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'CONNECT',
                              style: AppTextStyles.buttonText.copyWith(
                                fontSize: 17,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  divider('OR'),
                  const SizedBox(height: 20),
                  Text(
                    'OFFLINE MODE',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.orange.withValues(alpha: 0.88),
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Run JamBox without CRG. Use manual jam control.',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _goOffline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'START OFFLINE',
                        style: AppTextStyles.buttonText.copyWith(
                          fontSize: 15,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ),
                ],

                // ── Phase 2: Role selection (animated reveal) ────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: _showRoleSelector
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            const SizedBox(height: 24),

                            // Team settings (offline mode only)
                            if (_previewEngine?.isLocal == true &&
                                _previewState != null) ...[
                              Text(
                                'TEAM SETTINGS',
                                style: AppTextStyles.clockLabel.copyWith(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TeamSettingsSection(state: _previewState!),
                              const SizedBox(height: 24),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 24),
                            ],

                            Text(
                              'WHO DO YOU NEED TO SEE?',
                              style: AppTextStyles.clockLabel.copyWith(
                                color: Colors.white70,
                                fontSize: 13,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RoleSelector(
                              team1Name: _team1Name,
                              team2Name: _team2Name,
                              team1Color:
                                  _previewState?.team1.color ?? Colors.white,
                              team2Color:
                                  _previewState?.team2.color ?? Colors.black,
                              onTap: _startGame,
                            ),
                            const SizedBox(height: 24),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white24),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
    );
  }
}
