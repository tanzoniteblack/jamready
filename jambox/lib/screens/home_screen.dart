import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../services/local_penalty_engine.dart';
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

  AppRole _selectedRole = AppRole.pbm;
  int _selectedTeam = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('pbm_host') ?? '10.0.2.2';
      _portController.text = prefs.getString('pbm_port') ?? '8000';
      final roleName = prefs.getString('pbm_role');
      if (roleName != null) {
        _selectedRole = AppRole.values.firstWhere(
          (r) => r.name == roleName,
          orElse: () => AppRole.pbm,
        );
      }
      _selectedTeam = prefs.getInt('pbm_team') ?? 1;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pbm_host', _hostController.text.trim());
    await prefs.setString('pbm_port', _portController.text.trim());
    await prefs.setString('pbm_role', _selectedRole.name);
    await prefs.setInt('pbm_team', _selectedTeam);
  }

  Future<void> _connectAndGo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    await _saveSettings();

    if (!mounted) return;

    final state = PenaltyBoxState(
      role: _selectedRole,
      teamIndex: _selectedRole == AppRole.boxTimerTeam1
          ? 1
          : _selectedRole == AppRole.boxTimerTeam2
              ? 2
              : null,
    );

    final engine = RemotePenaltyEngine(state);
    final url = 'http://${_hostController.text.trim()}:${_portController.text.trim()}';
    engine.connect(url);

    if (!mounted) return;
    setState(() => _isLoading = false);
    _navigateToGame(state, engine);
  }

  Future<void> _goOffline() async {
    await _saveSettings();
    if (!mounted) return;

    final teamIdx = _selectedRole == AppRole.boxTimerTeam1
        ? 1
        : _selectedRole == AppRole.boxTimerTeam2
            ? 2
            : null;

    final state = PenaltyBoxState(role: _selectedRole, teamIndex: teamIdx);
    final engine = LocalPenaltyEngine(state);
    await engine.initialize();

    if (!mounted) return;
    _navigateToGame(state, engine);
  }

  void _navigateToGame(PenaltyBoxState state, dynamic engine) {
    Widget screen;
    switch (state.role) {
      case AppRole.pbm:
        screen = PbmScreen(engine: engine);
      case AppRole.boxTimerTeam1:
      case AppRole.boxTimerTeam2:
        screen = BoxTimerScreen(engine: engine);
      case AppRole.solo:
        screen = SoloScreen(engine: engine);
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: screen,
        ),
      ),
    );
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
                // Role selection
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
                  selected: _selectedRole,
                  onChanged: (r) => setState(() => _selectedRole = r),
                ),
                const SizedBox(height: 32),

                // CRG connection section
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
                    onPressed: _isLoading ? null : _connectAndGo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'CONNECT & START',
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
                const SizedBox(height: 24),
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

/// Role selector chips.
class _RoleSelector extends StatelessWidget {
  final AppRole selected;
  final ValueChanged<AppRole> onChanged;

  const _RoleSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _RoleOption(
              role: AppRole.pbm,
              selected: selected,
              label: 'PBM',
              subtitle: 'Both jammers',
              icon: Icons.swap_horiz,
              color: Colors.deepOrange.shade400,
              onTap: onChanged,
            )),
            const SizedBox(width: 10),
            Expanded(child: _RoleOption(
              role: AppRole.solo,
              selected: selected,
              label: 'Solo',
              subtitle: 'All seats',
              icon: Icons.grid_view,
              color: Colors.purple.shade400,
              onTap: onChanged,
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _RoleOption(
              role: AppRole.boxTimerTeam1,
              selected: selected,
              label: 'Timer T1',
              subtitle: 'Team 1 only',
              icon: Icons.timer,
              color: Colors.blue.shade400,
              onTap: onChanged,
            )),
            const SizedBox(width: 10),
            Expanded(child: _RoleOption(
              role: AppRole.boxTimerTeam2,
              selected: selected,
              label: 'Timer T2',
              subtitle: 'Team 2 only',
              icon: Icons.timer,
              color: Colors.red.shade400,
              onTap: onChanged,
            )),
          ],
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  final AppRole role;
  final AppRole selected;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final ValueChanged<AppRole> onTap;

  const _RoleOption({
    required this.role,
    required this.selected,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = role == selected;
    return GestureDetector(
      onTap: () => onTap(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: isSelected ? color : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.white38, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.clockLabel.copyWith(
                    color: isSelected ? color : Colors.white70,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.infoText.copyWith(fontSize: 11, color: Colors.white38),
                ),
              ],
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
