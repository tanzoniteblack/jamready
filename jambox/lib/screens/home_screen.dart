import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../services/local_penalty_engine.dart';
import '../services/penalty_engine.dart';
import '../services/remote_penalty_engine.dart';
import '../styles/background.dart';
import '../styles/text_styles.dart';
import 'box_timer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

    final url = 'http://${_hostController.text.trim()}:${_portController.text.trim()}';
    engine.connect(url);

    // Listen for team names to arrive, with a 3-second timeout fallback.
    _teamNameListener = () {
      if (state.teamNamesFromRemote) {
        _advanceToRoleSelector(state.team1.name, state.team2.name);
      }
    };
    state.addListener(_teamNameListener!);

    _teamNameTimer = Timer(const Duration(seconds: 3), () {
      _advanceToRoleSelector(_previewState?.team1.name ?? 'Salt', _previewState?.team2.name ?? 'Pepper');
    });

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
    _previewState = state;
    // _previewEngine stays null for offline

    // Listen to state changes to update team names live
    state.addListener(() {
      if (mounted) {
        setState(() {
          _team1Name = state.team1.name;
          _team2Name = state.team2.name;
        });
      }
    });

    if (!mounted) return;
    setState(() {
      _team1Name = 'Salt';
      _team2Name = 'Pepper';
      _showRoleSelector = true;
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

    if (_previewEngine != null) {
      // Reuse the live engine; update role on the existing state.
      state = _previewState!;
      state.role = role;
      state.teamIndex = teamIdx;
      engine = _previewEngine!;
      // Clear references so dispose() doesn't shut it down.
      _previewEngine = null;
      _previewState = null;
    } else {
      // Fresh offline path.
      state = _previewState ?? PenaltyBoxState();
      state.role = role;
      state.teamIndex = teamIdx;
      final localEngine = LocalPenaltyEngine(state);
      await localEngine.initialize();
      engine = localEngine;
      _previewState = null;
    }

    _activeEngine = engine;

    if (!mounted) return;

    Widget screen;
    switch (role) {
      case AppRole.pbm:
        screen = PbmScreen(engine: engine);
      case AppRole.team1BlockersOnly:
      case AppRole.team1Full:
      case AppRole.team2Full:
      case AppRole.team2BlockersOnly:
        screen = BoxTimerScreen(engine: engine);
      case AppRole.solo:
        screen = SoloScreen(engine: engine);
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: screen,
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
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QRScannerScreen()),
    );
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
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
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
                  style: AppTextStyles.clockLabel.copyWith(color: Colors.white38, fontSize: 12),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR ENTER MANUALLY',
                        style: AppTextStyles.clockLabel.copyWith(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _hostController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Host / IP Address', 'e.g. 192.168.1.100'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter a host address' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _portController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Port', 'e.g. 8000'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a port';
                    if (int.tryParse(v) == null) return 'Port must be a number';
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'CONNECT',
                              style: AppTextStyles.buttonText.copyWith(fontSize: 17),
                            ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white24)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: AppTextStyles.clockLabel.copyWith(color: Colors.white38, fontSize: 11)),
                      ),
                      Expanded(child: Divider(color: Colors.white24)),
                    ],
                  ),
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
                    style: AppTextStyles.clockLabel.copyWith(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _goOffline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'START OFFLINE',
                        style: AppTextStyles.buttonText.copyWith(fontSize: 15, color: Colors.orange),
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
                            Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                            const SizedBox(height: 24),

                            // Team settings (offline mode only)
                            if (_previewEngine == null && _previewState != null) ...[
                              Text(
                                'TEAM SETTINGS',
                                style: AppTextStyles.clockLabel.copyWith(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _TeamSettingsSection(state: _previewState!),
                              const SizedBox(height: 24),
                              Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
                              const SizedBox(height: 24),
                            ],

                            Text(
                              'YOUR ROLE',
                              style: AppTextStyles.clockLabel.copyWith(
                                color: Colors.white70,
                                fontSize: 13,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _RoleSelector(
                              team1Name: _team1Name,
                              team2Name: _team2Name,
                              team1Color: _previewState?.team1.color ?? Colors.white,
                              team2Color: _previewState?.team2.color ?? Colors.grey,
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

/// Role selector — each card starts the game immediately on tap.
class _RoleSelector extends StatelessWidget {
  final String team1Name;
  final String team2Name;
  final Color team1Color;
  final Color team2Color;
  final void Function(AppRole) onTap;

  const _RoleSelector({
    required this.team1Name,
    required this.team2Name,
    required this.team1Color,
    required this.team2Color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _RoleOption(
              role: AppRole.pbm,
              label: 'PBM',
              subtitle: 'Both jammers',
              icon: Icons.swap_horiz,
              color: Colors.deepOrange.shade400,
              onTap: onTap,
            )),
            const SizedBox(width: 10),
            Expanded(child: _RoleOption(
              role: AppRole.solo,
              label: 'Solo',
              subtitle: 'All seats',
              icon: Icons.grid_view,
              color: Colors.purple.shade400,
              onTap: onTap,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _RoleOption(
              role: AppRole.team1BlockersOnly,
              label: team1Name,
              subtitle: '3 blockers',
              icon: Icons.people_outline,
              color: team1Color,
              onTap: onTap,
            )),
            const SizedBox(width: 10),
            Expanded(child: _RoleOption(
              role: AppRole.team1Full,
              label: team1Name,
              subtitle: 'Jammer + blockers',
              icon: Icons.timer,
              color: team1Color,
              onTap: onTap,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _RoleOption(
              role: AppRole.team2BlockersOnly,
              label: team2Name,
              subtitle: '3 blockers',
              icon: Icons.people_outline,
              color: team2Color,
              onTap: onTap,
            )),
            const SizedBox(width: 10),
            Expanded(child: _RoleOption(
              role: AppRole.team2Full,
              label: team2Name,
              subtitle: 'Jammer + blockers',
              icon: Icons.timer,
              color: team2Color,
              onTap: onTap,
            )),
          ],
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  final AppRole role;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final void Function(AppRole) onTap;

  const _RoleOption({
    required this.role,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.clockLabel.copyWith(
                      color: color,
                      fontSize: 20,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTextStyles.infoText.copyWith(
                fontSize: 15,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── QR Scanner (reused from jamready) ────────────────────────────────────────

class _QRScannerScreen extends StatefulWidget {
  const _QRScannerScreen();

  @override
  State<_QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<_QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      _hasScanned = true;
      Navigator.of(context).pop(barcode!.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('SCAN QR CODE', style: AppTextStyles.appBarTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          CustomPaint(
            painter: _ScannerOverlayPainter(),
            child: const SizedBox.expand(),
          ),
          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Text(
              'Point your camera at the QR code\non the scoreboard\'s index page',
              textAlign: TextAlign.center,
              style: AppTextStyles.clockLabel.copyWith(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final cutoutSize = size.width * 0.7;
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 50),
      width: cutoutSize,
      height: cutoutSize,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)), borderPaint);

    final accentPaint = Paint()
      ..color = Colors.deepOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    final corners = [
      [cutoutRect.topLeft, Offset(cutoutRect.left + cornerLength, cutoutRect.top)],
      [cutoutRect.topLeft, Offset(cutoutRect.left, cutoutRect.top + cornerLength)],
      [cutoutRect.topRight, Offset(cutoutRect.right - cornerLength, cutoutRect.top)],
      [cutoutRect.topRight, Offset(cutoutRect.right, cutoutRect.top + cornerLength)],
      [cutoutRect.bottomLeft, Offset(cutoutRect.left + cornerLength, cutoutRect.bottom)],
      [cutoutRect.bottomLeft, Offset(cutoutRect.left, cutoutRect.bottom - cornerLength)],
      [cutoutRect.bottomRight, Offset(cutoutRect.right - cornerLength, cutoutRect.bottom)],
      [cutoutRect.bottomRight, Offset(cutoutRect.right, cutoutRect.bottom - cornerLength)],
    ];
    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Team Settings Section ────────────────────────────────────────────────────

const _teamColors = [
  Colors.white,
  Colors.grey,
  Colors.red,
  Colors.deepOrange,
  Colors.amber,
  Colors.green,
  Colors.blue,
  Colors.purple,
];

class _TeamSettingsSection extends StatelessWidget {
  final PenaltyBoxState state;

  const _TeamSettingsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TeamRow(teamIndex: 1, state: state),
        const SizedBox(height: 16),
        _TeamRow(teamIndex: 2, state: state),
      ],
    );
  }
}

class _TeamRow extends StatefulWidget {
  final int teamIndex;
  final PenaltyBoxState state;

  const _TeamRow({required this.teamIndex, required this.state});

  @override
  State<_TeamRow> createState() => _TeamRowState();
}

class _TeamRowState extends State<_TeamRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.teamInfo(widget.teamIndex).name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamInfo = widget.state.teamInfo(widget.teamIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Team ${widget.teamIndex}',
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: widget.teamIndex == 1 ? 'Salt' : 'Pepper',
            hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: teamInfo.color, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (value) {
            widget.state.updateTeam(widget.teamIndex, name: value);
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          children: _teamColors.map((color) {
            final isSelected = teamInfo.color == color;
            return GestureDetector(
              onTap: () => widget.state.setTeamColor(widget.teamIndex, color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: isSelected ? 3 : 0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
